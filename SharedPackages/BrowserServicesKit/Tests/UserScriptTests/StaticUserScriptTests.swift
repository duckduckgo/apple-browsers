//
//  StaticUserScriptTests.swift
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
@testable import UserScript

class StaticUserScriptTests: XCTestCase {
    class TestStaticUserScript: NSObject, StaticUserScript {
        nonisolated static let source: String = {
            do {
                return try TestStaticUserScript.loadJS("testUserScript", from: .module, withReplacements: ["${val}": "Test"])
            } catch {
                XCTFail("Failed to load testUserScript.js")
                return ""
            }
        }()
        nonisolated static let injectionTime: WKUserScriptInjectionTime = .atDocumentEnd
        nonisolated static let forMainFrameOnly: Bool = false
        static let script: WKUserScript = TestStaticUserScript.makeWKUserScript()

        nonisolated let messageNames: [String] = []

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        }
    }

    @MainActor
    func testWhenStaticWKUserScriptCreatedValuesInitializedCorrectly() async {
        let src = "var val = 'Test';\n"
        let us = TestStaticUserScript()
        let script = await us.makeWKUserScript().wkUserScript
        XCTAssertTrue(script.source.contains(src))
        XCTAssertEqual(script.injectionTime, .atDocumentEnd)
        XCTAssertEqual(script.isForMainFrameOnly, false)
    }

}
