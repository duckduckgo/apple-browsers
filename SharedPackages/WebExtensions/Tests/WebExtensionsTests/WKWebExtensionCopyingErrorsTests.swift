//
//  WKWebExtensionCopyingErrorsTests.swift
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

@testable import WebExtensions

/// WebKit throws `WKNSError` proxies; reading `localizedDescription` from one
/// crashes on x86_64. If the wrappers rethrow the proxy (`throw error` instead
/// of `throw NSError.webKitSafe(error)` in WKWebExtension+CopyingErrors.swift),
/// these tests fail on arm64 and crash under Rosetta (see
/// CPMMessagingDiagnosticsRecorderTests for the Rosetta commands).
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WKWebExtensionCopyingErrorsTests: XCTestCase {

    private static let validManifest = """
        {
            "manifest_version": 3, "name": "x", "description": "x",
            "version": "1"
        }
        """

    /// A content script without `matches` makes WebKit record an error.
    private static let manifestWithErrors = """
        {
            "manifest_version": 3, "name": "x", "description": "x",
            "version": "1", "content_scripts": [ { "js": ["a.js"] } ]
        }
        """

    private var extensionURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
        extensionURL = directory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        try writeManifest(Self.validManifest)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: extensionURL)
        extensionURL = nil
        super.tearDown()
    }

    // MARK: - Throwing wrappers

    func testWhenExtensionCannotBeCreated_ThenThrowsRealNSError() async {
        let missingURL = extensionURL.appendingPathComponent("missing")

        do {
            _ = try await SwiftWillThrowHook.disabled {
                try await WKWebExtension.makeCopyingErrors(at: missingURL)
            }
            XCTFail("Expected an error")
        } catch {
            assertRealNSError(error, domain: WKWebExtension.errorDomain)
        }
    }

    func testWhenContextIsLoadedTwice_ThenThrowsRealNSError() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try controller.loadCopyingErrors(context)
        defer { try? controller.unloadCopyingErrors(context) }

        do {
            try SwiftWillThrowHook.disabled {
                try controller.loadCopyingErrors(context)
            }
            XCTFail("Expected an error")
        } catch {
            let code = WKWebExtensionContext.Error.Code.alreadyLoaded
            let domain = WKWebExtensionContext.errorDomain
            assertRealNSError(error, domain: domain, code: code.rawValue)
        }
    }

    func testWhenContextIsNotLoaded_ThenUnloadThrowsRealNSError() async throws {
        let controller = makeController()
        let context = try await makeContext()

        do {
            try SwiftWillThrowHook.disabled {
                try controller.unloadCopyingErrors(context)
            }
            XCTFail("Expected an error")
        } catch {
            let code = WKWebExtensionContext.Error.Code.notLoaded
            let domain = WKWebExtensionContext.errorDomain
            assertRealNSError(error, domain: domain, code: code.rawValue)
        }
    }

    // MARK: - `errors` swizzling

    func testWhenErrorsAreSwizzled_ThenTheyAreRealNSErrors() async throws {
        WebExtensionErrorsSwizzling.install()
        try writeManifest(Self.manifestWithErrors)
        let url: URL = extensionURL
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        let context = WKWebExtensionContext(for: webExtension)

        for owner in [webExtension, context] as [NSObject] {
            let errorObjects = try errorObjects(of: owner)
            XCTAssertFalse(errorObjects.isEmpty)
            for errorObject in errorObjects {
                XCTAssertTrue(isRealNSError(errorObject))
            }
        }
        // On x86_64 this crashes when the getter still returns proxies.
        let firstError = try XCTUnwrap(context.errors.first)
        XCTAssertFalse(firstError.localizedDescription.isEmpty)
    }

    // MARK: - Helpers

    private func writeManifest(_ manifest: String) throws {
        let manifestURL = extensionURL.appendingPathComponent("manifest.json")
        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    private func makeController() -> WKWebExtensionController {
        WKWebExtensionController(configuration: .nonPersistent())
    }

    private func makeContext() async throws -> WKWebExtensionContext {
        let url: URL = extensionURL
        let webExtension = try await WKWebExtension.makeCopyingErrors(at: url)
        return WKWebExtensionContext(for: webExtension)
    }

    /// The `errors` objects as WebKit's getter returns them, without bridging.
    private func errorObjects(of owner: NSObject) throws -> [AnyObject] {
        try XCTUnwrap(owner.value(forKey: "errors") as? [AnyObject])
    }

    private func isRealNSError(_ object: AnyObject) -> Bool {
        let objectClass: AnyClass? = object_getClass(object)
        return objectClass.flatMap { $0 as? NSError.Type } != nil
    }

    private func assertRealNSError(
        _ error: Error,
        domain: String,
        code: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let isReal = isRealNSError(error as AnyObject)
        XCTAssertTrue(isReal, "Expected a real NSError", file: file, line: line)
        // On x86_64 this crashes when `error` is still a `WKNSError` proxy.
        let description = error.localizedDescription
        XCTAssertFalse(description.isEmpty, file: file, line: line)
        let nsError = NSError.webKitSafe(error)
        XCTAssertEqual(nsError.domain, domain, file: file, line: line)
        guard let code else { return }
        XCTAssertEqual(nsError.code, code, file: file, line: line)
    }

}
