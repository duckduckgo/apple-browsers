//
//  LocalModelAccessPromptTests.swift
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

import AIChat
import AppKit
import FeatureFlags_macOS
@_spi(Testing) import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import Testing
import WebKit
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Local model access pop-up")
final class LocalModelAccessPromptTests {

    private let pixelFiring = PixelKitMock()

    private func makePrompt() -> LocalModelAccessPrompt {
        let appearancePreferences = AppearancePreferences(persistor: AppearancePreferencesPersistorMock(),
                                                          privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                                          featureFlagger: MockFeatureFlagger(),
                                                          aiChatMenuConfig: MockAIChatConfig())
        return LocalModelAccessPrompt(themeManager: ThemeManager(appearancePreferences: appearancePreferences),
                                      instrumentation: LocalModelPixelInstrumentation(pixelFiring: pixelFiring))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page outside a window gets No Thanks, and no offer is counted", .timeLimit(.minutes(1)))
    func noWindowCountsNoOffer() async {
        let answer = await makePrompt().ask(from: nil, request: .connect(AIChatLocalModelInfo(id: "apple", name: "Apple Intelligence")))

        #expect(answer == .declined)
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page in a hidden window gets No Thanks, and no offer is counted", .timeLimit(.minutes(1)))
    func hiddenWindowCountsNoOffer() async {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView

        let answer = await makePrompt().ask(from: webView, request: .connect(AIChatLocalModelInfo(id: "apple", name: "Apple Intelligence")))

        #expect(answer == .declined)
        #expect(pixelFiring.actualFireCalls.isEmpty)
        #expect(webView.window === window && !window.isVisible)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing the pop-up without Turn On sends promo_closed", .timeLimit(.minutes(1)))
    func closingWithoutTurnOnSendsClosed() {
        let prompt = makePrompt()

        prompt.popoverDidClose(Notification(name: NSPopover.didCloseNotification))

        #expect(pixelFiring.actualFireCalls == [ExpectedFireCall(pixel: LocalModelPixelEvent(pixel: .promoClosed), frequency: .dailyAndCount)])
    }
}
