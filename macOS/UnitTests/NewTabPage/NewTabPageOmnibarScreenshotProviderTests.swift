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
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("New Tab Page screenshot provider")
struct NewTabPageOmnibarScreenshotProviderTests {

    @available(macOS 13, *)
    @Test("The flag off omits screenshot modes", .timeLimit(.minutes(1)))
    func flagOffOmitsModes() {
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: MockFeatureFlagger(), firePixel: { _ in })
        #expect(provider.screenshotModes == nil)
    }

    @available(macOS 13, *)
    @Test("The flag on offers both modes, Drag to Select first", .timeLimit(.minutes(1)))
    func flagOnOffersBothModes() {
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: makeFeatureFlagger(enabled: true), firePixel: { _ in })
        #expect(provider.screenshotModes == ["dragToSelect", "selectWindowOrDisplay"])
    }

    @available(macOS 13, *)
    @Test("The config changes only when the flag flips", .timeLimit(.minutes(1)))
    func configChangesOnlyWhenTheFlagFlips() {
        let featureFlagger = makeFeatureFlagger(enabled: false)
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: featureFlagger, firePixel: { _ in })
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
    @Test("A capture request with the flag off is a cancel and fires nothing", .timeLimit(.minutes(1)))
    func flagOffCaptureIsACancel() async {
        var pixels: [AIChatPixel] = []
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: MockFeatureFlagger(),
                                                           captureService: makeDeniedCaptureService(),
                                                           firePixel: { pixels.append($0) })
        let response = await provider.captureScreenshot(mode: "dragToSelect", requestingWebView: nil)
        #expect(response == .cancelled)
        #expect(pixels.isEmpty)
    }

    @available(macOS 13, *)
    @Test("An unknown mode is a cancel and fires nothing", .timeLimit(.minutes(1)))
    func unknownModeIsACancel() async {
        var pixels: [AIChatPixel] = []
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: makeFeatureFlagger(enabled: true),
                                                           captureService: makeDeniedCaptureService(),
                                                           firePixel: { pixels.append($0) })
        let response = await provider.captureScreenshot(mode: "unknown", requestingWebView: nil)
        #expect(response == .cancelled)
        #expect(pixels.isEmpty)
    }

    @available(macOS 13, *)
    @Test("A denied capture is a cancel for the page and fires the denied pixel", .timeLimit(.minutes(1)))
    func deniedCaptureIsACancelAndFiresDenied() async {
        var pixels: [AIChatPixel] = []
        let provider = NewTabPageOmnibarScreenshotProvider(featureFlagger: makeFeatureFlagger(enabled: true),
                                                           captureService: makeDeniedCaptureService(),
                                                           firePixel: { pixels.append($0) })
        let response = await provider.captureScreenshot(mode: "dragToSelect", requestingWebView: nil)
        #expect(response == .cancelled)
        #expect(pixels.map(\.name) == ["aichat_ntp_screenshot_failed"])
        #expect(pixels.first?.parameters == ["reason": "denied"])
    }

    // MARK: - Helpers

    private func makeFeatureFlagger(enabled: Bool) -> MockFeatureFlagger {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = enabled ? [.aiChatNtpScreenshot] : []
        return featureFlagger
    }

    /// Screen Recording off and the system prompt already raised once, so a capture ends before any UI.
    private func makeDeniedCaptureService() -> AIChatScreenshotCaptureService {
        let defaults = UserDefaults(suiteName: "NewTabPageOmnibarScreenshotProviderTests.\(UUID().uuidString)")!
        defaults.set(true, forKey: AIChatScreenRecordingPermission.hasRequestedKey)
        return AIChatScreenshotCaptureService(permission: AIChatScreenRecordingPermission(isGranted: { false },
                                                                                          requestAccess: {},
                                                                                          userDefaults: defaults))
    }
}
