//
//  NSErrorCopyingTests.swift
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

/// WebKit vends Web Extension errors as `WKNSError` proxies; bridging them with `as NSError` crashes on x86_64.
/// On arm64 the bridge happens to work, so these tests check that `NSError(copying:)` returns a real `NSError`.
@available(macOS 15.4, iOS 18.4, *)
final class NSErrorCopyingTests: XCTestCase {

    private struct SwiftError: Error {}

    private var extensionURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        extensionURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: extensionURL, withIntermediateDirectories: true)
        let manifest = #"{ "manifest_version": 3, "name": "x", "version": "1", "content_scripts": [ { "js": ["a.js"] } ] }"#
        try manifest.write(to: extensionURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: extensionURL)
        extensionURL = nil
        super.tearDown()
    }

    @MainActor
    func testWhenCopyingContextErrors_ThenCopiesAreRealNSErrors() async throws {
        let webExtension = try await WKWebExtension(resourceBaseURL: extensionURL)
        let context = WKWebExtensionContext(for: webExtension)

        let errors = context.errors.map(NSError.init(copying:))

        XCTAssertFalse(errors.isEmpty)
        for error in errors {
            XCTAssertTrue(isRealNSError(error))
            XCTAssertEqual(error.domain, WKWebExtension.errorDomain)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    @MainActor
    func testWhenCopyingThrownWebKitError_ThenCopyIsRealNSError() async throws {
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: extensionURL))

        do {
            try withoutSwiftWillThrowHook { try controller.unload(context) }
            XCTFail("Expected unloading a context that was never loaded to fail")
        } catch {
            let copy = NSError(copying: error)

            XCTAssertTrue(isRealNSError(copy))
            XCTAssertEqual(copy.domain, WKWebExtensionContext.errorDomain)
            XCTAssertEqual(copy.code, WKWebExtensionContext.Error.Code.notLoaded.rawValue)
        }
    }

    func testWhenCopyingErrorWithUnderlyingError_ThenUnderlyingErrorIsCopied() {
        let underlying = NSError(domain: "underlying", code: 2)
        let error = NSError(domain: "test", code: 1, userInfo: [NSUnderlyingErrorKey: underlying])

        let copy = NSError(copying: error)

        XCTAssertEqual(copy.domain, "test")
        XCTAssertEqual(copy.code, 1)
        XCTAssertEqual(copy.underlyingError?.domain, "underlying")
        XCTAssertEqual(copy.underlyingError?.code, 2)
    }

    func testWhenCopyingSwiftError_ThenDomainAndCodeArePreserved() {
        let copy = NSError(copying: SwiftError())

        XCTAssertTrue(copy.domain.hasSuffix("SwiftError"))
        XCTAssertEqual(copy.code, 1)
    }

    /// XCTest installs a `swift_willThrow` hook that, on x86_64, corrupts a thrown `WKNSError` before `catch` sees it.
    /// The app has no such hook, so the test runs the throwing call without it.
    private func withoutSwiftWillThrowHook<T>(_ body: () throws -> T) rethrows -> T {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        let hook = dlsym(rtldDefault, "_swift_willThrow")?.assumingMemoryBound(to: UnsafeRawPointer?.self)
        let savedHook = hook?.pointee
        hook?.pointee = nil
        defer { hook?.pointee = savedHook }
        return try body()
    }

    private func isRealNSError(_ error: NSError) -> Bool {
        object_getClass(error).flatMap { $0 as? NSError.Type } != nil
    }

}
