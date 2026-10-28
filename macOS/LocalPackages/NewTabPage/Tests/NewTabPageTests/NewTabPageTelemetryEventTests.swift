//
//  NewTabPageTelemetryEventTests.swift
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
@testable import NewTabPage

final class NewTabPageTelemetryEventTests: XCTestCase {

    private func decode(_ json: String) throws -> NewTabPageDataModel.TelemetryEvent {
        try JSONDecoder().decode(NewTabPageDataModel.TelemetryEvent.self, from: Data(json.utf8))
    }

    func testDecodesImageAndScreenshotEvents() throws {
        XCTAssertEqual(try decode(#"{"attributes":{"name":"omnibar_image_attached","value":{"source":"paste"}}}"#),
                       .omnibarImageAttached(source: "paste"))
        XCTAssertEqual(try decode(#"{"attributes":{"name":"omnibar_image_removed","value":{"source":"screenshot"}}}"#),
                       .omnibarImageRemoved(source: "screenshot"))
        XCTAssertEqual(try decode(#"{"attributes":{"name":"omnibar_screenshot_taken","value":{"kind":"selection"}}}"#),
                       .omnibarScreenshotTaken(kind: "selection"))
        XCTAssertEqual(try decode(#"{"attributes":{"name":"omnibar_screenshot_removed"}}"#),
                       .omnibarScreenshotRemoved)
        XCTAssertEqual(try decode(#"{"attributes":{"name":"omnibar_screenshot_failed","value":{"reason":"failed"}}}"#),
                       .omnibarScreenshotFailed(reason: "failed"))
    }

    func testAnEventMissingItsValueFailsToDecode() {
        XCTAssertThrowsError(try decode(#"{"attributes":{"name":"omnibar_screenshot_taken"}}"#))
    }
}
