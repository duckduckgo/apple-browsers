//
//  TabWebExtensionTabTests.swift
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

import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// Guards the one tab method CPM diagnostics call from inside a failure report.
///
/// When CPM messaging fails, `CPMMessagingDiagnosticsRecorder` takes a snapshot that asks every open tab for its
/// web view through `WKWebExtensionTab.webView(for:)`. `CPMMessagingDiagnosticsRecorderTests` (in the
/// `WebExtensions` package) only prove that this is the *only* tab method the recorder calls; they run against
/// test tabs. They cannot prove that the call is harmless on a real tab. This file does, for macOS `Tab`:
/// the call must be a plain read of the web view the tab already owns. It must not create a web view, start or
/// change a load, or otherwise change the tab, because a snapshot runs while the user's pages may be loading.
/// If `Tab.webView(for:)` ever creates or loads anything, these tests fail and the diagnostics need a rethink.
@available(macOS 15.4, *)
@MainActor
final class TabWebExtensionTabTests: XCTestCase {

    private var extensionDirectory: URL?

    override func tearDown() {
        if let extensionDirectory {
            try? FileManager.default.removeItem(at: extensionDirectory)
        }
        extensionDirectory = nil
        super.tearDown()
    }

    func testWebViewForContextReturnsTheWebViewTheTabAlreadyOwns() async throws {
        let tab = Tab(content: .none)
        let context = try await makeContext()

        XCTAssertTrue(tab.webView(for: context) === tab.webView)
    }

    func testWebViewForContextKeepsReturningTheSameWebView() async throws {
        let tab = Tab(content: .none)
        let context = try await makeContext()

        let first = tab.webView(for: context)
        let second = tab.webView(for: context)

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "reading the web view must not replace it")
    }

    func testWebViewForContextDoesNotStartALoadOrChangeTheTab() async throws {
        let tab = Tab(content: .none)
        let context = try await makeContext()
        let contentBefore = tab.content

        _ = tab.webView(for: context)
        _ = tab.webView(for: context)

        XCTAssertNil(tab.webView.url, "reading the web view must not navigate it")
        XCTAssertFalse(tab.webView.isLoading, "reading the web view must not start a load")
        XCTAssertEqual(tab.content, contentBefore, "reading the web view must not change what the tab shows")
    }

    // MARK: - Helpers

    /// A real context only so the call has an argument; `Tab.webView(for:)` ignores it.
    private func makeContext() async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TabWebExtensionTabTests-\(UUID().uuidString)")
        let manifest = """
        { "manifest_version": 3, "name": "Tab Test Extension", "version": "1.0.0" }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        extensionDirectory = directory
        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        return WKWebExtensionContext(for: webExtension)
    }
}
