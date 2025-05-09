//
//  UserScriptTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Foundation
import XCTest
import WebKit
import UserScript

class UserScriptTests: XCTestCase {

    class TestUserScript: NSObject, UserScript {
        var val: String
        lazy var source: String = {
            Self.loadJS("testUserScript", from: .module, withReplacements: ["${val}": val])
        }()
        var injectionTime: WKUserScriptInjectionTime
        var forMainFrameOnly: Bool
        var messageNames: [String]

        init(val: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool, messageNames: [String]) {
            self.val = val
            self.injectionTime = injectionTime
            self.forMainFrameOnly = forMainFrameOnly
            self.messageNames = messageNames
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        }
    }

    @MainActor
    func testWhenWKUserScriptCreatedValuesInitializedCorrectly() async {
        let src = "var val = 'Test';\n"
        let us = TestUserScript(val: "Test", injectionTime: .atDocumentStart, forMainFrameOnly: true, messageNames: [])
        let script = await us.makeWKUserScript().wkUserScript
        XCTAssertTrue(script.source.contains(src))
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertEqual(script.isForMainFrameOnly, true)
    }

    @MainActor
    func testWhenWKUserScriptCreatedValuesInitializedCorrectly2() async {
        let src = "var val = 'test2';\n"
        let us = TestUserScript(val: "test2", injectionTime: .atDocumentEnd, forMainFrameOnly: false, messageNames: [])
        let script = await us.makeWKUserScript().wkUserScript
        XCTAssertTrue(script.source.contains(src))
        XCTAssertEqual(script.injectionTime, .atDocumentEnd)
        XCTAssertEqual(script.isForMainFrameOnly, false)
    }

}
