//
//  DuckAiVoiceChatFailureHandlerTests.swift
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

import AVFoundation
import PixelKit
import PixelKitTestingUtilities
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DuckAiVoiceChatFailureHandlerTests: XCTestCase {

    private var presenter: SpyPermissionCenterPresenter!
    private var pixelFiring: PixelKitMock!
    private var authorizationStatus: AVAuthorizationStatus!
    private var sut: DuckAiVoiceChatFailureHandler!

    override func setUp() {
        super.setUp()
        presenter = SpyPermissionCenterPresenter()
        pixelFiring = PixelKitMock()
        authorizationStatus = .denied
        sut = DuckAiVoiceChatFailureHandler(
            microphoneAuthorizationStatusProvider: { [weak self] in
                self?.authorizationStatus ?? .denied
            },
            permissionCenterPresenter: presenter,
            pixelFiring: pixelFiring
        )
    }

    override func tearDown() {
        sut = nil
        authorizationStatus = nil
        pixelFiring = nil
        presenter = nil
        super.tearDown()
    }

    // MARK: - NotAllowedError + OS denied → request popover, no pixel from this layer

    /// `.micOsDenied` is fired by the receiver (`AddressBarButtonsViewController`) after it
    /// dedupes against its own popover state. The failure handler only requests the
    /// presentation; it must not fire the pixel itself or the count metric over-reports on
    /// rapid FE retries (the production presenter's dedupe probe always returns `false`).
    func testWhenNotAllowedErrorAndOSDenied_thenPresentsPopoverAndDoesNotFireMicOsDenied() {
        authorizationStatus = .denied

        sut.handleVoiceChatStartFailed(reason: "NotAllowedError", sourceWebView: nil)

        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenNotAllowedErrorAndOSRestricted_thenPresentsPopoverAndDoesNotFireMicOsDenied() {
        authorizationStatus = .restricted

        sut.handleVoiceChatStartFailed(reason: "NotAllowedError", sourceWebView: nil)

        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - NotAllowedError + OS NOT denied → no popover, fire `other`

    func testWhenNotAllowedErrorAndOSAuthorized_thenNoPopoverAndFiresOther() {
        authorizationStatus = .authorized

        sut.handleVoiceChatStartFailed(reason: "NotAllowedError", sourceWebView: nil)

        XCTAssertEqual(presenter.presentCount, 0)
        XCTAssertEqual(pixelFiring.actualFireCalls, [
            ExpectedFireCall(
                pixel: AIChatPixel.aiChatVoiceChatStartFailed(reason: .other),
                frequency: .dailyAndCount
            )
        ])
    }

    func testWhenNotAllowedErrorAndOSNotDetermined_thenNoPopoverAndFiresOther() {
        authorizationStatus = .notDetermined

        sut.handleVoiceChatStartFailed(reason: "NotAllowedError", sourceWebView: nil)

        XCTAssertEqual(presenter.presentCount, 0)
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters?["reason"],
                       AIChatVoiceChatStartFailedReason.other.rawValue)
    }

    // MARK: - Non-NotAllowedError → no popover, fire `other`

    func testWhenOtherReasonAndOSDenied_thenNoPopoverAndFiresOther() {
        authorizationStatus = .denied

        sut.handleVoiceChatStartFailed(reason: "AbortError", sourceWebView: nil)

        XCTAssertEqual(presenter.presentCount, 0)
        XCTAssertEqual(pixelFiring.actualFireCalls, [
            ExpectedFireCall(
                pixel: AIChatPixel.aiChatVoiceChatStartFailed(reason: .other),
                frequency: .dailyAndCount
            )
        ])
    }

    func testWhenEmptyReason_thenNoPopoverAndFiresOther() {
        authorizationStatus = .denied

        sut.handleVoiceChatStartFailed(reason: "", sourceWebView: nil)

        XCTAssertEqual(presenter.presentCount, 0)
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters?["reason"],
                       AIChatVoiceChatStartFailedReason.other.rawValue)
    }

    // MARK: - Dedupe

    func testWhenPopoverAlreadyPresented_thenNoPresentationAndNoPixel() {
        authorizationStatus = .denied
        presenter.isPresentedResult = true

        sut.handleVoiceChatStartFailed(reason: "NotAllowedError", sourceWebView: nil)

        XCTAssertEqual(presenter.presentCount, 0)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenSecondCallArrivesAfterPresent_thenPresenterDedupes() {
        // First call presents and "opens" the popover; second call sees it open and is suppressed.
        authorizationStatus = .denied

        sut.handleVoiceChatStartFailed(reason: "NotAllowedError", sourceWebView: nil)
        presenter.isPresentedResult = true
        sut.handleVoiceChatStartFailed(reason: "NotAllowedError", sourceWebView: nil)

        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }
}

// MARK: - Spy presenter

private final class SpyPermissionCenterPresenter: DuckAiVoiceChatPermissionCenterPresenting {

    var isPresentedResult: Bool = false
    private(set) var isPresentedCalls: [WKWebView?] = []
    private(set) var presentCount: Int = 0
    private(set) var presentedFor: [WKWebView?] = []
    private(set) var presentedSources: [DuckAiMicPermissionSource] = []

    @MainActor
    func isPermissionCenterPresented(for webView: WKWebView?) -> Bool {
        isPresentedCalls.append(webView)
        return isPresentedResult
    }

    @MainActor
    func presentPermissionCenter(for webView: WKWebView?, source: DuckAiMicPermissionSource) {
        presentCount += 1
        presentedFor.append(webView)
        presentedSources.append(source)
    }
}
