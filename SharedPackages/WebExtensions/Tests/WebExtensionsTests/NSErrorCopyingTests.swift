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

/// WebKit vends Web Extension errors as `WKNSError` proxies; bridging them
/// with `as NSError` crashes on x86_64. On arm64 the bridge happens to work,
/// so these tests check that `NSError.webKitSafe(_:)` returns real `NSError`s.
@available(macOS 15.4, iOS 18.4, *)
private typealias Controller = WKWebExtensionController

@available(macOS 15.4, iOS 18.4, *)
final class NSErrorCopyingTests: XCTestCase {

    private struct SwiftError: Error {}

    /// A content script without `matches` makes WebKit record an error.
    private static let manifest = """
        {
            "manifest_version": 3, "name": "x", "version": "1",
            "content_scripts": [ { "js": ["a.js"] } ]
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
        let manifestURL = extensionURL.appendingPathComponent("manifest.json")
        let manifest = Self.manifest
        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: extensionURL)
        extensionURL = nil
        super.tearDown()
    }

    // The `errors` swizzle may already have replaced these with real
    // `NSError`s; either way `webKitSafe` must hand back real ones.
    @MainActor
    func testWhenReadingContextErrors_ThenTheyAreRealNSErrors() async throws {
        let url: URL = extensionURL
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        let context = WKWebExtensionContext(for: webExtension)

        let errors = context.errors.map(NSError.webKitSafe)

        XCTAssertFalse(errors.isEmpty)
        for error in errors {
            XCTAssertTrue(isRealNSError(error))
            XCTAssertEqual(error.domain, WKWebExtension.errorDomain)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    // Thrown errors bypass the `errors` swizzle, so this always runs the
    // proxy-copying path, whatever other tests installed.
    @MainActor
    func testWhenWebKitThrowsProxy_ThenWebKitSafeCopiesIt() async throws {
        let url: URL = extensionURL
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        let context = WKWebExtensionContext(for: webExtension)
        let controller = Controller(configuration: .nonPersistent())

        do {
            try SwiftWillThrowHook.disabled { try controller.unload(context) }
            XCTFail("Unloading a context that was never loaded should fail")
        } catch {
            let proxy = error as AnyObject
            XCTAssertFalse(isRealNSError(proxy), "WebKit should throw a proxy")

            let copy = NSError.webKitSafe(error)

            let notLoaded = WKWebExtensionContext.Error.Code.notLoaded
            XCTAssertTrue(isRealNSError(copy))
            XCTAssertEqual(copy.domain, WKWebExtensionContext.errorDomain)
            XCTAssertEqual(copy.code, notLoaded.rawValue)
        }
    }

    @available(macOS 15.4, iOS 18.4, *)
    func testBackgroundContentLoadFailureMatchesOnlyContextDomainAndCode() {
        let failure = NSError(domain: WKWebExtensionContext.errorDomain,
                              code: WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue)
        XCTAssertTrue(failure.isBackgroundContentLoadFailure)
        for error in [NSError(domain: "other", code: failure.code),
                      NSError(domain: WKWebExtension.errorDomain, code: failure.code),
                      NSError(domain: failure.domain, code: WKWebExtensionContext.Error.Code.notLoaded.rawValue),
                      NSError(domain: "wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: failure])] {
            XCTAssertFalse(error.isBackgroundContentLoadFailure)
        }
    }

    func testWhenCopyingUnderlyingError_ThenItIsCopiedToo() {
        let underlying = NSError(domain: "underlying", code: 2)
        let userInfo = [NSUnderlyingErrorKey: underlying]
        let error = NSError(domain: "test", code: 1, userInfo: userInfo)

        let copy = NSError(copyingObject: error)

        XCTAssertEqual(copy.domain, "test")
        XCTAssertEqual(copy.code, 1)
        XCTAssertEqual(copy.underlyingError?.domain, "underlying")
        XCTAssertEqual(copy.underlyingError?.code, 2)
    }

    func testWhenCopyingSwiftError_ThenDomainAndCodeArePreserved() {
        let copy = NSError(copyingObject: SwiftError() as AnyObject)

        XCTAssertTrue(copy.domain.hasSuffix("SwiftError"))
        XCTAssertEqual(copy.code, 1)
    }

    func testWhenErrorIsRealNSError_ThenWebKitSafeDoesNotCopyIt() {
        let error = NSError(domain: "test", code: 1)

        XCTAssertIdentical(NSError.webKitSafe(error), error)
    }

    func testWhenErrorIsSwiftError_ThenWebKitSafeKeepsDomainAndCode() {
        let nsError = NSError.webKitSafe(SwiftError())

        XCTAssertTrue(nsError.domain.hasSuffix("SwiftError"))
        XCTAssertEqual(nsError.code, 1)
    }

    func testWhenObjectIsNotAnError_ThenCopyIsUnexpectedError() {
        let copy = NSError(copyingObject: NSObject())

        XCTAssertEqual(copy.domain, "WebExtensionsUnexpectedError")
        XCTAssertEqual(copy.code, 0)
    }

    private func isRealNSError(_ object: AnyObject) -> Bool {
        let objectClass: AnyClass? = object_getClass(object)
        return objectClass.flatMap { $0 as? NSError.Type } != nil
    }

}
