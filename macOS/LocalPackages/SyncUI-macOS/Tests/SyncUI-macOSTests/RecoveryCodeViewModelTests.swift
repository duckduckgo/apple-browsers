//
//  RecoveryCodeViewModelTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import AppKit
import XCTest
@testable import SyncUI_macOS

final class RecoveryCodeViewModelTests: XCTestCase {

    override func tearDown() {
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    func testSubmitButtonIsDisabledByDefault() throws {
        let model = RecoveryCodeViewModel()
        XCTAssertTrue(model.shouldDisableSubmitButton)
    }

    func testWhenPastingV2PairingURLThenCodeIsPreserved() {
        let model = RecoveryCodeViewModel()
        let url = "https://duckduckgo.com/sync/pairing/#&code2=eyJ2ZXJzaW9uIjoiMi4wIn0"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)

        model.paste()

        XCTAssertEqual(model.recoveryCode, url)
    }

    func testWhenPastingCodeWithWhitespaceThenWhitespaceIsRemoved() {
        let model = RecoveryCodeViewModel()
        let input = " https://duckduckgo.com/sync/pairing/\n#&code2=abc \n"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(input, forType: .string)

        model.paste()

        XCTAssertEqual(model.recoveryCode, "https://duckduckgo.com/sync/pairing/#&code2=abc")
    }
}
