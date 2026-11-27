//
//  WebExtensionReloadErrorPixelMetadataTests.swift
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

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionReloadErrorPixelMetadataTests: XCTestCase {

    func testReloadErrorPixelMetadataIncludesDomainAndCode() {
        let metadata = WebExtensionReloadErrorPixelMetadata(
            type: .embedded,
            trigger: .dataClearing,
            phase: .lightweightLoad,
            error: NSError(
                domain: WKWebExtensionContext.errorDomain,
                code: WKWebExtensionContext.Error.Code.baseURLAlreadyInUse.rawValue
            )
        )

        XCTAssertEqual(WebExtensionReloadErrorPixelMetadata.name, "debug_web_extension_reload_failed")
        XCTAssertEqual(metadata.parameters, [
            "extension_type": "embedded",
            "reload_trigger": "data_clearing",
            "reload_phase": "light_load",
            "d": WKWebExtensionContext.errorDomain,
            "e": String(WKWebExtensionContext.Error.Code.baseURLAlreadyInUse.rawValue)
        ])
    }

    func testReloadErrorPixelPreservesUnknownDomainAndUnderlyingCodeWithoutUserInfo() {
        let underlying = NSError(domain: NSURLErrorDomain, code: -1009,
                                 userInfo: [NSLocalizedDescriptionKey: "https://private.example/path"])
        let error = NSError(domain: "CustomReloadError", code: 42,
                            userInfo: [NSUnderlyingErrorKey: underlying, NSFilePathErrorKey: "/Users/private/file"])
        let metadata = WebExtensionReloadErrorPixelMetadata(type: nil, trigger: .explicit, phase: .load, error: error)

        XCTAssertEqual(metadata.parameters, [
            "extension_type": "unknown",
            "reload_trigger": "explicit",
            "reload_phase": "load",
            "d": "CustomReloadError",
            "e": "42",
            "ud": NSURLErrorDomain,
            "ue": "-1009"
        ])
    }
}
