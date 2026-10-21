//
//  NewTabPageOmnibarScreenshotProviderTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import FeatureFlags_macOS
import NewTabPage
@_spi(Testing) import PixelKit
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("New Tab Page screenshot provider")
struct NewTabPageOmnibarScreenshotProviderTests {

    @available(macOS 13, *)
    @Test("The flag off omits screenshot modes", .timeLimit(.minutes(1)))
    func flagOffOmitsModes() {
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: MockFeatureFlagger(), pixelFiring: nil)
        #expect(provider.screenshotModes == nil)
    }

    @available(macOS 13, *)
    @Test("The flag on offers both modes, Drag to Select first", .timeLimit(.minutes(1)))
    func flagOnOffersBothModes() {
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: makeFeatureFlagger(enabled: true), pixelFiring: nil)
        #expect(provider.screenshotModes == ["dragToSelect", "selectWindowOrDisplay"])
    }

    @available(macOS 13, *)
    @Test("The config changes only when the flag flips", .timeLimit(.minutes(1)))
    func configChangesOnlyWhenTheFlagFlips() {
        let featureFlagger = makeFeatureFlagger(enabled: false)
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: featureFlagger, pixelFiring: nil)
        var changes = 0
        let cancellable = provider.configChangesPublisher.sink { changes += 1 }

        featureFlagger.triggerUpdate()
        #expect(changes == 0)

        featureFlagger.enabledFeatureFlags = [.aiChatNtpScreenshot]
        featureFlagger.triggerUpdate()
        featureFlagger.triggerUpdate()
        #expect(changes == 1)

        featureFlagger.enabledFeatureFlags = []
        featureFlagger.triggerUpdate()
        #expect(changes == 2)
        cancellable.cancel()
    }

    @available(macOS 13, *)
    @Test("Pasted attachments follow their own flag, and flipping it changes the config", .timeLimit(.minutes(1)))
    func pastedAttachmentsFollowTheirFlag() {
        let featureFlagger = MockFeatureFlagger()
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: featureFlagger, pixelFiring: nil)
        var changes = 0
        let cancellable = provider.configChangesPublisher.sink { changes += 1 }
        #expect(provider.enablePastedAttachments == false)

        featureFlagger.enabledFeatureFlags = [.aiChatNtpPasteImages]
        featureFlagger.triggerUpdate()
        #expect(provider.enablePastedAttachments == true)
        #expect(provider.screenshotModes == nil)
        #expect(changes == 1)
        cancellable.cancel()
    }

    @available(macOS 13, *)
    @Test("A capture request with the flag off is a cancel and fires nothing", .timeLimit(.minutes(1)))
    func flagOffCaptureIsACancel() async {
        let pixels = PixelKitMock()
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: MockFeatureFlagger(),
                                                           captureService: makeDeniedCaptureService(),
                                                           pixelFiring: pixels)
        let response = await provider.captureScreenshot(mode: "dragToSelect", requestingWebView: nil)
        #expect(response == .cancelled)
        #expect(pixels.actualFireCalls.isEmpty)
    }

    @available(macOS 13, *)
    @Test("An unknown mode is a cancel and fires nothing", .timeLimit(.minutes(1)))
    func unknownModeIsACancel() async {
        let pixels = PixelKitMock()
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: makeFeatureFlagger(enabled: true),
                                                           captureService: makeDeniedCaptureService(),
                                                           pixelFiring: pixels)
        let response = await provider.captureScreenshot(mode: "unknown", requestingWebView: nil)
        #expect(response == .cancelled)
        #expect(pixels.actualFireCalls.isEmpty)
    }

    @available(macOS 13, *)
    @Test("A denied capture is a cancel for the page and fires the denied pixel", .timeLimit(.minutes(1)))
    func deniedCaptureIsACancelAndFiresDenied() async {
        let pixels = PixelKitMock()
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: makeFeatureFlagger(enabled: true),
                                                           captureService: makeDeniedCaptureService(),
                                                           pixelFiring: pixels)
        let response = await provider.captureScreenshot(mode: "dragToSelect", requestingWebView: nil)
        #expect(response == .cancelled)
        #expect(pixels.actualFireCalls.map(\.pixel.name) == ["aichat_ntp_screenshot_failed"])
        #expect(pixels.actualFireCalls.first?.pixel.parameters == ["reason": "denied"])
        #expect(pixels.actualFireCalls.first?.frequency == .dailyAndCount)
    }

    @available(macOS 13, *)
    @Test("The page's image and screenshot telemetry fires the matching pixel, and drops values it doesn't know", .timeLimit(.minutes(1)))
    func pageTelemetryFiresTheMatchingPixel() {
        let cases: [(event: NewTabPageDataModel.TelemetryEvent, name: String?, parameters: [String: String])] = [
            (.omnibarImageAttached(source: "paste"), "aichat_ntp_image_attached", ["source": "paste"]),
            (.omnibarImageRemoved(source: "screenshot"), "aichat_ntp_image_removed", ["source": "screenshot"]),
            (.omnibarScreenshotTaken(kind: "window"), "aichat_ntp_screenshot_taken", ["kind": "window"]),
            (.omnibarScreenshotRemoved, "aichat_ntp_screenshot_removed", [:]),
            (.omnibarScreenshotFailed(reason: "denied"), "aichat_ntp_screenshot_failed", ["reason": "denied"]),
            (.omnibarScreenshotFailed(reason: "unknown"), nil, [:])
        ]
        for testCase in cases {
            let pixels = PixelKitMock()
            NewTabPageConfigurationEventHandler(pixelFiring: pixels).fire(.newTabPageTelemetry(payload: testCase.event))

            #expect(pixels.actualFireCalls.map(\.pixel.name) == (testCase.name.map { [$0] } ?? []), "\(testCase.event)")
            #expect((pixels.actualFireCalls.first?.pixel.parameters ?? [:]) == testCase.parameters, "\(testCase.event)")
            #expect(pixels.actualFireCalls.allSatisfy { $0.frequency == .dailyAndCount })
        }
    }

    // MARK: - Helpers

    private func makeFeatureFlagger(enabled: Bool) -> MockFeatureFlagger {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = enabled ? [.aiChatNtpScreenshot] : []
        return featureFlagger
    }

    /// Screen Recording off, so a capture ends before any UI.
    private func makeDeniedCaptureService() -> AIChatScreenshotCaptureService {
        AIChatScreenshotCaptureService(permission: AIChatScreenRecordingPermission(isGranted: { false }, requestAccess: {}),
                                       instrumentation: AIChatScreenshotPermissionInstrumentationSpy())
    }
}
