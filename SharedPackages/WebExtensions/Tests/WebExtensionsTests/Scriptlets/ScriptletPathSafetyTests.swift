//
//  ScriptletPathSafetyTests.swift
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

final class ScriptletPathSafetyTests: XCTestCase {

    // MARK: - validateName

    func testWhenNameIsSimpleFilenameThenValidationSucceeds() {
        XCTAssertNoThrow(try ScriptletPathSafety.validateName("script.js"))
    }

    func testWhenNameHasSubdirectoriesThenValidationSucceeds() {
        XCTAssertNoThrow(try ScriptletPathSafety.validateName("scriptlets/nested/script.js"))
    }

    func testWhenNameIsEmptyThenValidationThrows() {
        XCTAssertThrowsError(try ScriptletPathSafety.validateName("")) { error in
            XCTAssertEqual(error as? ScriptletError, .invalidName(name: ""))
        }
    }

    func testWhenNameIsAbsolutePathThenValidationThrows() {
        XCTAssertThrowsError(try ScriptletPathSafety.validateName("/etc/passwd")) { error in
            XCTAssertEqual(error as? ScriptletError, .invalidName(name: "/etc/passwd"))
        }
    }

    func testWhenNameStartsWithDoubleSlashThenValidationThrows() {
        XCTAssertThrowsError(try ScriptletPathSafety.validateName("//evil.js"))
    }

    func testWhenNameContainsParentSegmentThenValidationThrows() {
        XCTAssertThrowsError(try ScriptletPathSafety.validateName("../evil.js"))
        XCTAssertThrowsError(try ScriptletPathSafety.validateName("foo/../../evil.js"))
        XCTAssertThrowsError(try ScriptletPathSafety.validateName("foo/bar/.."))
        XCTAssertThrowsError(try ScriptletPathSafety.validateName(".."))
    }

    func testWhenNameContainsCurrentDirSegmentThenValidationThrows() {
        XCTAssertThrowsError(try ScriptletPathSafety.validateName("./script.js"))
        XCTAssertThrowsError(try ScriptletPathSafety.validateName("foo/./script.js"))
    }

    func testWhenNameContainsNulByteThenValidationThrows() {
        XCTAssertThrowsError(try ScriptletPathSafety.validateName("script\u{0}.js"))
    }

    func testWhenNameLooksLikeTraversalButIsEmbeddedInSegmentThenValidationSucceeds() {
        // "..js" / "foo..bar" are not `..` segments and should be allowed.
        XCTAssertNoThrow(try ScriptletPathSafety.validateName("..js"))
        XCTAssertNoThrow(try ScriptletPathSafety.validateName("foo..bar/script.js"))
    }

    // MARK: - ensureContained

    func testWhenURLIsInsideBaseThenContainmentSucceeds() throws {
        let base = URL(fileURLWithPath: "/tmp/base")
        let inside = base.appendingPathComponent("a/b.js")
        XCTAssertNoThrow(try ScriptletPathSafety.ensureContained(inside, within: base, name: "a/b.js"))
    }

    func testWhenURLEqualsBaseThenContainmentSucceeds() throws {
        let base = URL(fileURLWithPath: "/tmp/base")
        XCTAssertNoThrow(try ScriptletPathSafety.ensureContained(base, within: base, name: ""))
    }

    func testWhenURLEscapesBaseViaTraversalThenContainmentThrows() {
        let base = URL(fileURLWithPath: "/tmp/base")
        let outside = base.appendingPathComponent("../evil.js")
        XCTAssertThrowsError(try ScriptletPathSafety.ensureContained(outside, within: base, name: "../evil.js")) { error in
            XCTAssertEqual(error as? ScriptletError, .pathEscapesBase(name: "../evil.js"))
        }
    }

    func testWhenURLIsSiblingOfBaseThenContainmentThrows() {
        let base = URL(fileURLWithPath: "/tmp/base")
        let sibling = URL(fileURLWithPath: "/tmp/basement/file.js")
        XCTAssertThrowsError(try ScriptletPathSafety.ensureContained(sibling, within: base, name: "basement/file.js"))
    }
}
