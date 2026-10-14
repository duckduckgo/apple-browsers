//
//  ResolvedFunnelOriginTests.swift
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
@testable import Subscription

final class ResolvedFunnelOriginTests: XCTestCase {

    private static let nativeOrigin = "funnel_appsettings_test"

    func testResolveIsNilWhenOriginIsMissing() {
        XCTAssertNil(resolve(nil))
        XCTAssertNil(resolve(""))
    }

    func testResolveReturnsNativeForNativeOrigin() {
        XCTAssertEqual(resolve(Self.nativeOrigin), .native)
    }

    func testResolveReturnsWebForWebOrigin() {
        XCTAssertEqual(resolve("funnel_web_a", webOrigins: ["funnel_web_a"]), .web)
    }

    func testResolveReturnsUnknownForOtherOrigins() {
        XCTAssertEqual(resolve("funnel_web_b", webOrigins: ["funnel_web_a"]), .unknown(reportableOrigin: "funnel_web_b"))
    }

    func testResolveReportsUnknownOriginOnlyWhenItLooksLikeAFunnelOrigin() {
        XCTAssertEqual(resolve("Funnel_Web_A"), .unknown(reportableOrigin: "funnel_web_a"))
        XCTAssertEqual(resolve("funnel_" + String(repeating: "a", count: 64)),
                       .unknown(reportableOrigin: "funnel_" + String(repeating: "a", count: 64)))
        XCTAssertEqual(resolve("funnel_" + String(repeating: "a", count: 65)), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolve("not_a_funnel"), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolve("funnel_"), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolve("funnel_a-b"), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolve("funnel_a@example.com"), .unknown(reportableOrigin: nil))
        XCTAssertEqual(resolve("https://example.com/funnel_a"), .unknown(reportableOrigin: nil))
    }

    private func resolve(_ origin: String?, webOrigins: Set<String> = []) -> ResolvedFunnelOrigin? {
        ResolvedFunnelOrigin.resolve(origin, isNativeOrigin: { $0 == Self.nativeOrigin }, webOrigins: webOrigins)
    }
}
