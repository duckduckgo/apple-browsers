//
//  WebExtensionManifestKeyPatcherTests.swift
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

import XCTest
@testable import WebExtensions

final class WebExtensionManifestKeyPatcherTests: XCTestCase {

    private let patcher = WebExtensionManifestKeyPatcher()
    private let manifestDirectory = URL(fileURLWithPath: "/tmp/extension")
    private let bitwardenKey = WebExtensionManifestKeyPatcher.knownPublicKeys["Bitwarden"]

    func testWhenKnownExtensionHasNoKey_ThenKeyIsInserted() {
        var manifest: [String: Any] = ["name": "Bitwarden Password Manager", "short_name": "Bitwarden"]

        let changed = patcher.insertKnownPublicKeyIfNeeded(in: &manifest, manifestDirectory: manifestDirectory)

        XCTAssertTrue(changed)
        XCTAssertEqual(manifest["key"] as? String, bitwardenKey)
    }

    func testWhenNameIsALocalizationPlaceholder_ThenShortNameIsUsed() {
        var manifest: [String: Any] = ["name": "__MSG_extName__", "short_name": "Bitwarden"]

        let changed = patcher.insertKnownPublicKeyIfNeeded(in: &manifest, manifestDirectory: manifestDirectory)

        XCTAssertTrue(changed)
        XCTAssertEqual(manifest["key"] as? String, bitwardenKey)
    }

    func testWhenManifestAlreadyHasKey_ThenItIsLeftAlone() {
        var manifest: [String: Any] = ["short_name": "Bitwarden", "key": "existing"]

        let changed = patcher.insertKnownPublicKeyIfNeeded(in: &manifest, manifestDirectory: manifestDirectory)

        XCTAssertFalse(changed)
        XCTAssertEqual(manifest["key"] as? String, "existing")
    }

    func testWhenExtensionIsUnknown_ThenNoKeyIsInserted() {
        var manifest: [String: Any] = ["name": "Some Extension"]

        let changed = patcher.insertKnownPublicKeyIfNeeded(in: &manifest, manifestDirectory: manifestDirectory)

        XCTAssertFalse(changed)
        XCTAssertNil(manifest["key"])
    }
}
