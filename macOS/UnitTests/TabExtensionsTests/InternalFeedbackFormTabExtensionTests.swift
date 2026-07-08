//
//  InternalFeedbackFormTabExtensionTests.swift
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
import JavaScriptCore
import PrivacyConfig
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class InternalFeedbackFormTabExtensionTests: XCTestCase {

    private var webViewSubject: PassthroughSubject<WKWebView, Never>!
    private var internalUserDecider: MockInternalUserDecider!
    private var builderInvocations: [(quickMode: Bool, diagnostics: String, screenshotBase64: String)]!

    override func setUp() {
        super.setUp()
        webViewSubject = PassthroughSubject<WKWebView, Never>()
        internalUserDecider = MockInternalUserDecider(isInternalUser: true)
        builderInvocations = []
    }

    override func tearDown() {
        webViewSubject = nil
        internalUserDecider = nil
        builderInvocations = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Returns a tagged script string so tests can assert which inputs the builder was called with.
    private func recordingBuilder() -> InternalFeedbackFormTabExtension.ScriptSourceBuilder {
        return { [weak self] quickMode, diagnostics, screenshotBase64 in
            self?.builderInvocations.append((quickMode, diagnostics, screenshotBase64))
            return "SCRIPT|quick=\(quickMode)|diag=\(diagnostics)|shot=\(screenshotBase64)"
        }
    }

    private func makeExtension(
        builder: InternalFeedbackFormTabExtension.ScriptSourceBuilder? = nil
    ) -> InternalFeedbackFormTabExtension {
        InternalFeedbackFormTabExtension(
            webViewPublisher: webViewSubject,
            internalUserDecider: internalUserDecider,
            scriptSourceBuilder: builder ?? recordingBuilder()
        )
    }

    // MARK: - Default (no popup context)

    func testWhenPopupContextIsNilThenScriptSourceUsesDefaultBuilderArguments() {
        let ext = makeExtension()

        let source = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(source, "SCRIPT|quick=false|diag=|shot=")
        XCTAssertEqual(builderInvocations.count, 1)
        XCTAssertEqual(builderInvocations[0].quickMode, false)
        XCTAssertEqual(builderInvocations[0].diagnostics, "")
        XCTAssertEqual(builderInvocations[0].screenshotBase64, "")
    }

    func testWhenPopupContextIsNilThenDefaultScriptSourceIsCachedAcrossCalls() {
        let ext = makeExtension()

        _ = ext.scriptSourceForCurrentNavigation()
        _ = ext.scriptSourceForCurrentNavigation()
        _ = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(builderInvocations.count, 1, "Default script source should be built once and cached")
    }

    // MARK: - Popup context

    func testWhenPopupContextIsSetThenScriptSourceReflectsContextValues() {
        let ext = makeExtension()
        ext.popupContext = InternalFeedbackFormPopupContext(
            quickMode: true,
            diagnostics: "diag-payload",
            screenshotData: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )

        let source = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(source, "SCRIPT|quick=true|diag=diag-payload|shot=3q2+7w==")
    }

    func testWhenPopupContextScreenshotIsNilThenScreenshotBase64IsEmpty() {
        let ext = makeExtension()
        ext.popupContext = InternalFeedbackFormPopupContext(
            quickMode: true,
            diagnostics: "no-shot",
            screenshotData: nil
        )

        _ = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(builderInvocations.count, 1)
        XCTAssertEqual(builderInvocations[0].screenshotBase64, "", "Nil screenshot should map to empty string, not the literal \"nil\"")
    }

    func testWhenPopupContextChangesBetweenCallsThenScriptIsRebuiltWithLatestValues() {
        let ext = makeExtension()

        ext.popupContext = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "first", screenshotData: nil)
        let firstSource = ext.scriptSourceForCurrentNavigation()

        ext.popupContext = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "second", screenshotData: Data([0x01, 0x02]))
        let secondSource = ext.scriptSourceForCurrentNavigation()

        XCTAssertNotEqual(firstSource, secondSource, "A changed popup context must produce a freshly built script")
        XCTAssertEqual(builderInvocations.count, 2)
        XCTAssertEqual(builderInvocations[0].diagnostics, "first")
        XCTAssertEqual(builderInvocations[1].diagnostics, "second")
        XCTAssertEqual(builderInvocations[1].screenshotBase64, "AQI=")
    }

    func testWhenSamePopupContextIsUsedTwiceThenScriptIsStillRebuiltEachCall() {
        let ext = makeExtension()
        ext.popupContext = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "same", screenshotData: nil)

        _ = ext.scriptSourceForCurrentNavigation()
        _ = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(builderInvocations.count, 2, "Popup mode must rebuild the script per call so reopening picks up a fresh screenshot")
    }

    // MARK: - Reverting to default

    func testWhenPopupContextIsSetThenClearedThenSubsequentCallReturnsCachedDefault() {
        let ext = makeExtension()

        // Prime the cached default first so the call count is deterministic.
        _ = ext.scriptSourceForCurrentNavigation()
        XCTAssertEqual(builderInvocations.count, 1)

        ext.popupContext = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "popup", screenshotData: nil)
        _ = ext.scriptSourceForCurrentNavigation()
        XCTAssertEqual(builderInvocations.count, 2)

        ext.popupContext = nil
        let afterClear = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(afterClear, "SCRIPT|quick=false|diag=|shot=")
        XCTAssertEqual(builderInvocations.count, 2, "Clearing popup context should revert to the cached default without rebuilding")
    }

    // MARK: - JS literal escaping (regression: diagnostics with newlines/quotes/separators)

    /// Diagnostics include arbitrary user/system text — newlines, apostrophes, backslashes, and
    /// even U+2028/U+2029 (which terminate JS string literals). The helper must produce a literal
    /// that parses as valid JavaScript and round-trips back to the original string.
    func testJSStringLiteralProducesValidJSLiteralForAdversarialInput() throws {
        let adversarial = """
        Line 1 with 'apostrophe' and "quote"
        Line 2 with backslash \\ and literal \\n sequence
        Line 3 with U+2028 line sep:\u{2028}and U+2029 para sep:\u{2029}end
        Line 4 with carriage return\rand tab\tand null \0 byte
        Line 5 with </script> closer and Unicode 🦆
        """

        let literal = InternalFeedbackFormUserScript.jsStringLiteral(adversarial)

        let context = try XCTUnwrap(JSContext())
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }

        let result = context.evaluateScript("(\(literal))")

        XCTAssertNil(exception, "jsStringLiteral output must parse as JavaScript. Error: \(exception?.toString() ?? "")")
        XCTAssertEqual(result?.toString(), adversarial, "JS literal must round-trip back to the original string")
    }

    func testJSStringLiteralProducesEmptyStringLiteralForEmptyInput() throws {
        let literal = InternalFeedbackFormUserScript.jsStringLiteral("")

        let context = try XCTUnwrap(JSContext())
        let result = context.evaluateScript("(\(literal))")

        XCTAssertEqual(result?.toString(), "")
    }

    // MARK: - Protocol exposure

    func testProtocolExposesReadWritePopupContext() {
        let ext = makeExtension()
        let asProtocol: any InternalFeedbackFormTabExtensionProtocol = ext

        XCTAssertNil(asProtocol.popupContext)

        let context = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "via-protocol", screenshotData: nil)
        asProtocol.popupContext = context

        XCTAssertEqual(asProtocol.popupContext?.quickMode, true)
        XCTAssertEqual(asProtocol.popupContext?.diagnostics, "via-protocol")
        XCTAssertNil(asProtocol.popupContext?.screenshotData)
    }
}

/// Behavioural tests for the screenshot-attachment logic in `internal-feedback-autofiller.js`,
/// run via JavaScriptCore against a minimal DOM stub (`domStub` below). Bypasses the promise/
/// `MutationObserver`-based async init flow and calls the setup functions directly, using the
/// real production script from `InternalFeedbackFormUserScript`.
@MainActor
final class InternalFeedbackFormAutofillerScreenshotTests: XCTestCase {

    // A 1×1 transparent PNG — small enough to be fast, valid enough that the
    // script produces a non-empty screenshotBase64 value.
    private static let minimalPngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

    // MARK: - Helpers

    private func productionScript(base64: String) -> String {
        InternalFeedbackFormUserScript(quickMode: true, diagnostics: "", screenshotBase64: base64).source
    }

    /// Loads the DOM stub and production script, then runs the setup calls `hideIrrelevantFields()`
    /// makes in production. `attachLabelInDom: false` simulates the attachment row not yet being
    /// in the DOM at init, for testing the lazy-retry fix in `attachScreenshotToForm()`.
    private func makeContext(
        base64: String = minimalPngBase64,
        attachLabelInDom: Bool = true
    ) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        var caughtException: JSValue?
        context.exceptionHandler = { _, value in caughtException = value }

        context.evaluateScript(Self.domStub)
        context.evaluateScript("_attachLabelInDom = \(attachLabelInDom);")
        context.evaluateScript(productionScript(base64: base64))
        context.evaluateScript("""
            injectScreenshotSection();
            showAndRelabelAttachmentRow();
            hookSubmitForDiagnostics();
            """)

        XCTAssertNil(caughtException, "Stub or production script threw: \(caughtException?.toString() ?? "")")
        return context
    }

    private func fileCount(_ context: JSContext) -> Int {
        Int(context.evaluateScript("_fileCount()")?.toInt32() ?? -1)
    }

    // MARK: - Tests

    func testNoFilesBeforeAnyInteraction() throws {
        let context = try makeContext()

        XCTAssertEqual(fileCount(context), 0)
    }

    /// Ticking must not eagerly write to the file input — Asana's React state would capture it
    /// immediately, uploading the screenshot even if the user unticks before submitting.
    func testTickingCheckboxDoesNotWriteToFileInput() throws {
        let context = try makeContext()

        context.evaluateScript("_tickScreenshotCheckbox();")

        XCTAssertEqual(fileCount(context), 0)
    }

    func testSubmitWithCheckboxCheckedAttachesScreenshotFile() throws {
        let context = try makeContext()

        context.evaluateScript("_tickScreenshotCheckbox(); _clickSubmit();")

        XCTAssertEqual(fileCount(context), 1)
    }

    func testSubmitWithCheckboxUncheckedDoesNotAttachFile() throws {
        let context = try makeContext()

        context.evaluateScript("_clickSubmit();")

        XCTAssertEqual(fileCount(context), 0)
    }

    func testSubmitWithCheckboxCheckedAndExistingUserFilePreservesBothFiles() throws {
        let context = try makeContext()

        context.evaluateScript("""
            _seedUserFile('my-attachment.pdf');
            _tickScreenshotCheckbox();
            _clickSubmit();
            """)

        XCTAssertEqual(fileCount(context), 2)
    }

    func testScreenshotSectionNotInjectedWhenNoBase64() throws {
        let context = try makeContext(base64: "")

        let sectionExists = context.evaluateScript("_screenshotSectionExists()")?.toBool() ?? true

        XCTAssertFalse(sectionExists)
    }

    /// Regression: if the attachment row isn't in the DOM yet when `hideIrrelevantFields()` runs
    /// its one-shot `showAndRelabelAttachmentRow()` call, `attachScreenshotToForm()` must retry
    /// marking it at submit time rather than silently attaching nothing.
    func testSubmitAttachesScreenshotWhenAttachRowRendersAfterInitialInjection() throws {
        let context = try makeContext(attachLabelInDom: false)

        context.evaluateScript("""
            _makeAttachLabelAvailable();
            _tickScreenshotCheckbox();
            _clickSubmit();
            """)

        XCTAssertEqual(fileCount(context), 1)
    }

    // MARK: - DOM stub

    /// Minimal DOM stub so `injectScreenshotSection()`, `showAndRelabelAttachmentRow()`, and
    /// `hookSubmitForDiagnostics()` can run in a bare JSContext.
    private static let domStub = #"""
    var setTimeout = function(fn, ms) { return 1; };
    var clearTimeout = function() {};
    var setInterval = function(fn, ms) { return 1; };
    var clearInterval = function() {};

    var console = { error: function() {}, log: function() {}, warn: function() {} };

    // Shadows JavaScriptCore's built-in Promise so waitForElement()'s chain
    // never resolves/rejects — keeps these tests deterministic regardless of
    // microtask timing, mirroring the Jint-based Windows test stub.
    var Promise = function(executor) {
        try { executor(function() {}, function() {}); } catch (e) {}
        this.then = function() { return this; };
        this.catch = function() { return this; };
    };

    var MutationObserver = function() {
        return { observe: function() {}, disconnect: function() {} };
    };

    var atob = function(s) { return ''; };
    var Blob = function() {};
    var File = function(parts, name) { this.name = name; };
    var Event = function(type, opts) { this.type = type; this.bubbles = !!(opts && opts.bubbles); };

    var DataTransfer = function() {
        var _files = [];
        this.items = { add: function(f) { _files.push(f); } };
        Object.defineProperty(this, 'files', { get: function() { return _files; } });
    };

    // hookSubmitForDiagnostics() calls Object.getOwnPropertyDescriptor(
    //   window.HTMLTextAreaElement.prototype, 'value').set to drive React's value;
    // stub it to a plain property assignment so the call succeeds.
    var window = {};
    window.HTMLTextAreaElement = { prototype: {} };
    window.HTMLInputElement    = { prototype: {} };
    Object.getOwnPropertyDescriptor = function(obj, prop) {
        if (prop === 'value') { return { set: function(v) { this.value = v; } }; }
        return { value: obj[prop], writable: true, enumerable: true, configurable: true };
    };

    var _elementsById = {};

    function _el(tag) {
        var el = {
            _tag: tag, _children: [], _listeners: {}, _id: '',
            type: '', src: '', title: '', textContent: '', checked: false,
            files: [], value: '', style: { cssText: '', display: '' },
            parentNode: null, nextSibling: null,
            setAttribute: function(k, v) { this[k] = v; },
            getAttribute: function(k) { return this[k] !== undefined ? this[k] : null; },
            appendChild: function(c) { c.parentNode = this; this._children.push(c); return c; },
            insertBefore: function(n) { n.parentNode = this; return n; },
            querySelector: function(sel) {
                for (var i = 0; i < this._children.length; i++) {
                    var c = this._children[i];
                    if (_matches(c, sel)) return c;
                    var found = c.querySelector ? c.querySelector(sel) : null;
                    if (found) return found;
                }
                return null;
            },
            closest: function() { return null; },
            addEventListener: function(type, fn, cap) {
                if (!this._listeners[type]) this._listeners[type] = [];
                this._listeners[type].push({ fn: fn, cap: !!cap });
            },
            dispatchEvent: function(e) {
                (this._listeners[e.type] || []).forEach(function(h) { h.fn(e); });
            }
        };
        Object.defineProperty(el, 'id', {
            get: function() { return el._id; },
            set: function(v) { el._id = v; _elementsById[v] = el; },
            configurable: true
        });
        return el;
    }

    function _matches(el, sel) {
        if (!el || !sel) return false;
        if (sel === 'textarea') return el._tag === 'textarea';
        if (sel === 'input[type="file"]') return el._tag === 'input' && el.type === 'file';
        return false;
    }

    var _textarea = _el('textarea');
    _textarea.value = 'smoke test feedback';

    // Description label. hookSubmitForDiagnostics finds this to reach the textarea.
    var _descLabel = _el('label');
    _descLabel.textContent = 'Please describe your issue/feedback';

    var _descRow = _el('div');
    _descRow.appendChild(_descLabel);
    _descRow.appendChild(_textarea);
    _descLabel.closest = function(sel) {
        return (sel === '.WorkRequestsFieldRow') ? _descRow : null;
    };
    _descRow.querySelector = function(sel) {
        return (sel === 'textarea') ? _textarea : null;
    };

    var _fileInput = _el('input');
    _fileInput.type = 'file';

    // Attachment label. showAndRelabelAttachmentRow() searches for this text.
    var _attachLabel = _el('label');
    _attachLabel.textContent = 'If available, attach any screenshots';

    // Attachment row. showAndRelabelAttachmentRow() marks this with data-ddg-attach-row.
    var _attachRow = _el('div');
    _attachRow.appendChild(_attachLabel);
    _attachRow.appendChild(_fileInput);
    _attachLabel.closest = function(sel) {
        return (sel === '.WorkRequestsFieldRow') ? _attachRow : null;
    };
    _attachRow.querySelector = function(sel) {
        return (sel === 'input[type="file"]') ? _fileInput : null;
    };

    // The real submit button that hookSubmitForDiagnostics hooks.
    var _submitBtn = _el('button');

    // An anchor div that stands in for ddg-submit-clone so injectDiagnosticsSection()
    // and injectScreenshotSection() have a valid insertion point.
    var _submitClone = _el('div');
    _submitClone._id = 'ddg-submit-clone';
    _elementsById['ddg-submit-clone'] = _submitClone;

    // Form body: parent node for all the above so insertBefore calls succeed.
    var _formBody = _el('div');
    _formBody.appendChild(_descRow);
    _formBody.appendChild(_attachRow);
    _formBody.appendChild(_submitBtn);
    _formBody.appendChild(_submitClone);
    _submitClone.parentNode = _formBody;

    // Whether the attachment label is discoverable via querySelectorAll('label') yet.
    // Defaults to true (row present immediately, as in the common case). Tests that
    // need to simulate Asana rendering the row *after* the initial hideIrrelevantFields()
    // pass can flip this to false before init and call _makeAttachLabelAvailable() later.
    var _attachLabelInDom = true;

    function _visibleLabels() {
        return _attachLabelInDom ? [_descLabel, _attachLabel] : [_descLabel];
    }

    var document = {
        body: _formBody,
        createElement: function(tag) { return _el(tag); },
        getElementById: function(id) { return _elementsById[id] || null; },
        querySelector: function(sel) {
            // data-ddg-attach-row is set by showAndRelabelAttachmentRow() at runtime.
            if (sel === '[data-ddg-attach-row]') {
                return (_attachRow['data-ddg-attach-row'] === 'true') ? _attachRow : null;
            }
            if (sel.indexOf('WorkRequestsSubmissionForm-submitButton') !== -1) return _submitBtn;
            if (sel === '#ddg-screenshot-section img') {
                var sec = _elementsById['ddg-screenshot-section'];
                if (!sec) return null;
                for (var i = 0; i < sec._children.length; i++) {
                    if (sec._children[i]._tag === 'img') return sec._children[i];
                }
                return null;
            }
            return null;
        },
        querySelectorAll: function(sel) {
            return (sel === 'label') ? _visibleLabels() : [];
        },
        evaluate: function() { return { singleNodeValue: null }; }
    };

    // True when injectScreenshotSection() has created the section node.
    function _screenshotSectionExists() {
        return !!_elementsById['ddg-screenshot-section'];
    }

    // Number of files currently in the hidden file input.
    function _fileCount() {
        return (_fileInput.files && _fileInput.files.length) ? _fileInput.files.length : 0;
    }

    // Pre-seed a user-selected file so merge tests can verify it is preserved.
    function _seedUserFile(name) {
        _fileInput.files = [{ name: name || 'user-file.txt' }];
    }

    // Simulate ticking the Include screenshot checkbox.
    function _tickScreenshotCheckbox() {
        var cb = document.getElementById('ddg-include-screenshot');
        if (!cb) throw new Error('ddg-include-screenshot not found - call injectScreenshotSection() first');
        cb.checked = true;
        cb.dispatchEvent(new Event('change', { bubbles: true }));
    }

    // Simulate clicking the submit button (triggers the capture-phase listener).
    function _clickSubmit() {
        _submitBtn.dispatchEvent(new Event('click', { bubbles: true }));
    }

    // Simulate Asana rendering the attachment row after the initial init pass.
    function _makeAttachLabelAvailable() {
        _attachLabelInDom = true;
    }
    """#
}
