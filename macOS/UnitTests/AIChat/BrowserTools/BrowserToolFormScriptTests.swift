//
//  BrowserToolFormScriptTests.swift
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
import SharedTestUtilities
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// Runs `BrowserToolForms.js` against a real page. The web view has no window on purpose: Duck.ai's
/// tabs are background tabs, so the script has to work without one.
@MainActor
final class BrowserToolFormScriptTests: XCTestCase {

    private var webView: WKWebView!
    private var driver: WebViewFormDriver!

    override func setUp() {
        super.setUp()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        driver = WebViewFormDriver()
    }

    override func tearDown() {
        webView = nil
        driver = nil
        super.tearDown()
    }

    func testWhenThePageIsReadThenEveryLabelSourceIsFound() async throws {
        let page = try await loadFixture()

        XCTAssertEqual(try field("fullName", in: page).labels.labelFor, "Full name")
        XCTAssertEqual(try field("company", in: page).labels.wrapping, "Company")
        XCTAssertEqual(try field("city", in: page).labels.ariaLabel, "City")
        XCTAssertEqual(try field("zip", in: page).labels.ariaLabelledBy, "ZIP code")
        XCTAssertEqual(try field("notes", in: page).labels.placeholder, "Anything else?")
        XCTAssertEqual(try field("size", in: page).labels.labelFor, "Home size")
    }

    func testWhenARadioGroupIsLabelledByNearbyTextThenTheGroupGetsThatLabel() async throws {
        let page = try await loadFixture()

        let group = try XCTUnwrap(BrowserToolForms.fields(in: page).first { $0.type == "radio" })

        XCTAssertEqual(group.label, "Do you own or rent?")
        XCTAssertEqual(group.options, [.init(value: "own", label: "I own"), .init(value: "rent", label: "I rent")])
    }

    func testWhenAStepIsHiddenThenItsFieldsAreNotVisible() async throws {
        let page = try await loadFixture()

        XCTAssertFalse(try field("later", in: page).visible)
        XCTAssertFalse(try field("token", in: page).visible)
        XCTAssertTrue(try field("fullName", in: page).visible)
    }

    func testWhenAFieldIsAPasswordThenItsValueNeverLeavesThePage() async throws {
        let page = try await loadFixture()

        let password = try field("pw", in: page)
        XCTAssertEqual(password.type, "password")
        XCTAssertNil(password.value)
    }

    func testWhenButtonsAreReadThenTheirTypeAttributeAndFormAreReported() async throws {
        let page = try await loadFixture()

        let next = try XCTUnwrap(page.buttons.first { $0.text == "Next" })
        let submit = try XCTUnwrap(page.buttons.first { $0.text == "Get my quote" })
        let outside = try XCTUnwrap(page.buttons.first { $0.text == "Outside" })
        XCTAssertEqual(next.typeAttribute, "button")
        XCTAssertNil(submit.typeAttribute)
        XCTAssertTrue(submit.inForm)
        XCTAssertFalse(outside.inForm)
        XCTAssertTrue(BrowserToolForms.isSubmit(submit))
        XCTAssertFalse(BrowserToolForms.isSubmit(next))
    }

    func testWhenThePageIsReadTwiceThenRefsStayTheSame() async throws {
        let first = try await loadFixture()
        let second = try unwrapped(await driver.page(in: webView))

        XCTAssertEqual(first.fields.map(\.ref), second.fields.map(\.ref))
        XCTAssertEqual(first.buttons.map(\.ref), second.buttons.map(\.ref))
        XCTAssertEqual(BrowserToolForms.siteName(of: first), "Example Movers")
    }

    /// The registry lives in Duck.ai's own world, out of the page's reach.
    func testWhenThePageLooksForTheScriptThenItCannotSeeIt() async throws {
        _ = try await loadFixture()

        let visibleToPage = try await webView.callAsyncJavaScript("return typeof globalThis.__duckAIForms", contentWorld: .page) as? String

        XCTAssertEqual(visibleToPage, "undefined")
    }

    func testWhenFieldsAreFilledThenThePageSeesInputAndChangeAndTheValuesReadBack() async throws {
        let page = try await loadFixture()
        let name = try field("fullName", in: page)
        let size = try field("size", in: page)
        let packing = try field("packing", in: page)

        let readback = try unwrapped(await driver.apply([
            .text(ref: name.ref, value: "P"),
            .select(ref: size.ref, value: "2br"),
            .check(ref: packing.ref, checked: true)
        ], in: webView))

        XCTAssertEqual(readback.map(\.value), ["P", "2br", "on"])
        XCTAssertEqual(readback.last?.checked, true)
        let events = try await webView.callAsyncJavaScript("return window.events.join(',')", contentWorld: .page) as? String
        XCTAssertEqual(events, "input,change")
    }

    /// The page writes its message into `<id>-error` on change, as the quote sites do.
    func testWhenThePageShowsAValidationErrorAfterFillingThenItIsReportedForThatField() async throws {
        let page = try await loadFixture()
        let name = try field("fullName", in: page)

        _ = await driver.apply([.text(ref: name.ref, value: "P")], in: webView)
        let after = try unwrapped(await driver.page(in: webView))

        XCTAssertEqual(try field("fullName", in: after).error, "Too short.")
        XCTAssertEqual(BrowserToolForms.errors(in: after), [.init(ref: name.ref, message: "Too short.")])
    }

    func testWhenAFormIsSubmittedThenThePageReceivesTheSubmitWithItsButton() async throws {
        let page = try await loadFixture()
        let form = try XCTUnwrap(page.forms.first { $0.name == "quote" })
        let submit = try XCTUnwrap(page.buttons.first { $0.text == "Get my quote" })

        let submitted = await driver.submit(formRef: form.ref, submitterRef: submit.ref, in: webView)

        XCTAssertTrue(submitted)
        let submitter = try await webView.callAsyncJavaScript("return window.submitter", contentWorld: .page) as? String
        XCTAssertEqual(submitter, "Get my quote")
    }

    func testWhenAButtonIsClickedThenThePageHandlesItAndChangesAreTracked() async throws {
        let page = try await loadFixture()
        let next = try XCTUnwrap(page.buttons.first { $0.text == "Next" })

        let clicked = await driver.click(next.ref, in: webView)
        let sinceChange = await driver.millisecondsSinceLastChange(in: webView)

        XCTAssertTrue(clicked)
        XCTAssertNotNil(sinceChange)
        let after = try unwrapped(await driver.page(in: webView))
        XCTAssertTrue(try field("later", in: after).visible)
        let clickedMissing = await driver.click("b999", in: webView)
        XCTAssertFalse(clickedMissing)
    }

    // MARK: -

    private func loadFixture() async throws -> BrowserToolRawPage {
        let loaded = expectation(description: "loaded")
        let delegate = TestNavigationDelegate(e: loaded)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(Self.fixture, baseURL: URL(string: "https://quotes.example/movers")!)
        await fulfillment(of: [loaded], timeout: 5)
        withExtendedLifetime(delegate) {}
        return try unwrapped(await driver.page(in: webView))
    }

    private func field(_ name: String, in page: BrowserToolRawPage) throws -> BrowserToolRawPage.Field {
        try XCTUnwrap(page.fields.first { $0.name == name }, "no field named \(name)")
    }

    private func unwrapped<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }

    /// Modelled on the hackdays quote sites, but written for these tests.
    private static let fixture = """
    <!DOCTYPE html>
    <html><head><title>Get a quote | Example Movers</title><meta property="og:site_name" content="Example Movers"></head>
    <body><main>
      <form id="quote" name="quote" novalidate>
        <div class="field"><label for="full-name">Full name</label><input id="full-name" name="fullName" required><div class="error" id="full-name-error"></div></div>
        <label>Company <input name="company"></label>
        <input name="city" aria-label="City">
        <span id="zip-label">ZIP code</span><input name="zip" aria-labelledby="zip-label">
        <textarea name="notes" placeholder="Anything else?"></textarea>
        <div class="field"><span class="label">Do you own or rent?</span>
          <div class="choice"><label><input type="radio" name="ownership" value="own"> I own</label><label><input type="radio" name="ownership" value="rent"> I rent</label></div>
          <div class="error" id="ownership-error"></div></div>
        <div class="field"><label for="size">Home size</label><select id="size" name="size"><option value="">Choose…</option><option value="2br">2 bedrooms</option></select></div>
        <div class="field check"><input type="checkbox" id="packing" name="packing"><label for="packing">Add packing</label></div>
        <div class="field"><label for="pw">Create a password</label><input type="password" id="pw" name="pw" value="secret" autocomplete="new-password"></div>
        <input type="hidden" name="token" value="abc">
        <fieldset id="step-2" hidden><legend>Later</legend><label for="later">Later field</label><input id="later" name="later"></fieldset>
        <button type="button" id="next">Next</button>
        <button>Get my quote</button>
      </form>
      <button id="outside">Outside</button>
    </main>
    <script>
      window.events = [];
      const fullName = document.getElementById('full-name');
      ['input', 'change'].forEach((type) => fullName.addEventListener(type, () => window.events.push(type)));
      fullName.addEventListener('change', () => {
        document.getElementById('full-name-error').textContent = fullName.value.length < 2 ? 'Too short.' : '';
      });
      document.getElementById('next').addEventListener('click', () => { document.getElementById('step-2').hidden = false; });
      document.getElementById('quote').addEventListener('submit', (event) => {
        event.preventDefault();
        window.submitter = event.submitter ? event.submitter.textContent : null;
      });
    </script>
    </body></html>
    """
}
