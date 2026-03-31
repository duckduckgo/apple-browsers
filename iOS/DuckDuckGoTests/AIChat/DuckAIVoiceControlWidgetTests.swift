//
//  DuckAIVoiceControlWidgetTests.swift
//  DuckDuckGo
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

import XCTest
@testable import Core
@testable import DuckDuckGo

final class DuckAIVoiceControlWidgetTests: XCTestCase {

    // MARK: - ControlWidgetKind

    func testVoiceChatControlWidgetKindHasCorrectRawValue() {
        XCTAssertEqual(ControlWidgetKind.voiceChat.rawValue, "VoiceChatControlWidget")
    }

    // MARK: - Widget Configuration

    @available(iOS 18, *)
    func testVoiceChatControlWidgetHasCorrectConfiguration() {
        let widget = DuckAIVoiceChatControlWidget()

        XCTAssertEqual(widget.kind, .voiceChat)
        XCTAssertEqual(widget.labelText, "Duck.ai Voice")
        XCTAssertEqual(widget.imageName, "AIVoiceChat-Symbol")
    }

    // MARK: - Deep Link URL

    func testVoiceChatDeepLinkHasSourceParameter() {
        let url = AppDeepLinkSchemes.openAIVoiceChat.url
            .appendingParameter(name: "source", value: "control_center")

        XCTAssertEqual(AppDeepLinkSchemes.fromURL(url), .openAIVoiceChat)
        XCTAssertEqual(url.getParameter(named: "source"), "control_center")
    }
}
