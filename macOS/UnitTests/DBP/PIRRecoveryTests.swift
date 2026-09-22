//
//  PIRRecoveryTests.swift
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

#if DEBUG && compiler(>=6.4) && canImport(FoundationModels)
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 27.0, *)
@MainActor
final class PIRRecoveryTests: XCTestCase {
    private let formAction: [String: Any] = [
        "id": "fill", "actionType": "fillForm", "selector": "#removal",
        "elements": [["type": "firstName", "selector": ".//input[@name='first']"]]
    ]

    private func load(_ html: String) async -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let waiter = NavigationWaiter(expectation: expectation(description: "Local HTML loaded"))
        webView.navigationDelegate = waiter
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [waiter.expectation], timeout: 5)
        webView.navigationDelegate = nil
        return webView
    }

    func testWhenGeneratingSelectorThenUsesUniqueAttributesClassesOrShortScope() async throws {
        let fixtures: [(html: String, selector: String)] = [
            ("<button id='opt-out'>Recover</button>", "#opt-out"),
            ("<button id='opt:out'>Recover</button>", #"#opt\:out"#),
            ("<button name='remove'>Recover</button>", "button[name=remove]"),
            ("<button aria-label='Recover'>Recover</button>", "button[aria-label=Recover]"),
            ("<button class='btn opt-out-button'>Recover</button><button class='btn'>Other</button>", "button.opt-out-button"),
            ("<button class='btn primary'>Recover</button><button class='btn'>Other</button><div class='primary'></div>", "button.primary"),
            ("<button id='duplicate' class='remove'>Recover</button><button id='duplicate'>Other</button>", "button.remove"),
            ("<main id='removal'><button class='next'>Recover</button></main><footer><button class='next'>Other</button></footer>",
             "#removal button.next"),
            ("<div><button>Other</button><button>Recover</button></div>", "button:nth-child(2)"),
            ("<button hidden class='next'>Other</button><main><button class='next'>Recover</button></main>", "main button.next"),
            ("<form id='removal'><button name='next'>Recover</button></form>", "button[name=next]")
        ]
        for fixture in fixtures {
            let webView = await load(fixture.html)
            let capture = try await webView.evaluateJavaScript(PIRRecoverySnapshot.script, in: nil, contentWorld: .page)
            let json = try XCTUnwrap(capture as? String)
            let snapshot = try JSONDecoder().decode(PIRRecoverySnapshot.self, from: Data(json.utf8))
            let target = try XCTUnwrap(snapshot.elements.first { $0.label == "Recover" })
            let script = try PIRRecoverySnapshot.targetValidationScript(captureID: snapshot.captureID, elementID: target.id)
            let result = try await webView.evaluateJavaScript(script, in: nil, contentWorld: .page)
            let resultJSON = try XCTUnwrap(result as? String)
            let selection = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(resultJSON.utf8)) as? [String: String])
            XCTAssertNil(selection["error"], fixture.html)
            XCTAssertEqual(selection["selector"], fixture.selector, fixture.html)
            XCTAssertEqual(selection["formSelector"], fixture.html.contains("<form") ? "#removal" : "body")
        }
    }

    func testWhenCapturedNodeIsReplacedThenRejectsIdenticalSelector() async throws {
        let webView = await load("<button id='next'>Recover</button>")
        let capture = try await webView.evaluateJavaScript(PIRRecoverySnapshot.script, in: nil, contentWorld: .page)
        let snapshot = try JSONDecoder().decode(PIRRecoverySnapshot.self, from: Data(XCTUnwrap(capture as? String).utf8))
        let target = try XCTUnwrap(snapshot.elements.first { $0.label == "Recover" })
        _ = try await webView.evaluateJavaScript("document.querySelector('button').outerHTML = '<button id=next>Recover</button>'",
                                                in: nil, contentWorld: .page)
        let script = try PIRRecoverySnapshot.targetValidationScript(captureID: snapshot.captureID, elementID: target.id)
        let result = try await webView.evaluateJavaScript(script, in: nil, contentWorld: .page)
        XCTAssertTrue(try XCTUnwrap(result as? String).contains("The target or its form state changed"))
    }

    func testRecoveryUsesFormGoalAndRejectsUnrelatedFooterControl() async throws {
        let webView = await load("""
        <main><section><h1>Remove your personal listing</h1><button>Continue</button>
        <input value="private-field-value"><div contenteditable="true">private-edited-text</div>
        </section></main><footer><button>View more</button></footer>
        """)
        let value = try await webView.evaluateJavaScript(PIRRecoverySnapshot.script, in: nil, contentWorld: .page)
        let json = try XCTUnwrap(value as? String)
        let snapshot = try JSONDecoder().decode(PIRRecoverySnapshot.self, from: Data(json.utf8))
        let button = try XCTUnwrap(snapshot.elements.first { $0.label == "Continue" })
        XCTAssertEqual(button.landmark, "main")
        XCTAssertTrue(button.surroundingText.contains("Remove your personal listing"))
        XCTAssertFalse(json.contains("private-field-value"))
        XCTAssertFalse(json.contains("private-edited-text"))

        let broken: [String: Any] = ["id": "broken", "actionType": "click", "elements": [["type": "button", "selector": "#missing"]]]
        let later: [String: Any] = ["id": "later", "actionType": "navigate", "url": "https://example.invalid/later"]
        let distant = later.merging(["id": "distant"]) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: ["stepType": "optOut", "actions": [broken, formAction, later, distant]])
        let context = try PIRRecoveryContext(stepJSON: XCTUnwrap(String(data: data, encoding: .utf8)), completedActionCount: 0,
                                             failedActionID: "broken", availableData: [])
        let candidates = PIRRecoveryActionBuilder.candidates(snapshot: snapshot, context: context)
        XCTAssertEqual(candidates.map(\.elementID), [button.id])
        XCTAssertTrue(context.recoveryObjective.contains("firstName"))
        XCTAssertFalse(try context.modelSequenceJSON().contains("distant"))
    }

    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        let expectation: XCTestExpectation

        init(expectation: XCTestExpectation) {
            self.expectation = expectation
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            expectation.fulfill()
        }
    }
}
#endif
