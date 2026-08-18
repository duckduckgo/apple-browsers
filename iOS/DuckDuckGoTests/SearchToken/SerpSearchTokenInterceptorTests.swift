//
//  SerpSearchTokenInterceptorTests.swift
//  DuckDuckGo
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
import Common
@testable import DuckDuckGo

final class SerpSearchTokenInterceptorTests: XCTestCase {

    // MARK: isSerpURL

    func testIsSerpURL_trueForSearchResults() {
        let url = URL(string: "https://duckduckgo.com/?q=privacy")!
        XCTAssertTrue(SerpSearchTokenInterceptor.isSerpURL(url))
    }

    func testIsSerpURL_falseForNonSearchDuckDuckGo() {
        let url = URL(string: "https://duckduckgo.com/about")!
        XCTAssertFalse(SerpSearchTokenInterceptor.isSerpURL(url))
    }

    func testIsSerpURL_falseForDuckAIChatQuery() {
        let url = URL(string: "https://duckduckgo.com/?q=hello&ia=chat")!
        XCTAssertFalse(SerpSearchTokenInterceptor.isSerpURL(url))
    }

    func testIsSerpURL_falseForNonDuckDuckGo() {
        let url = URL(string: "https://example.com/?q=privacy")!
        XCTAssertFalse(SerpSearchTokenInterceptor.isSerpURL(url))
    }
    
    // MARK: - signalledRequest: dindexexp param

    func testSignalledRequest_appendsDindexB_forTreatment() {
        let out = SerpSearchTokenInterceptor.signalledRequest(for: serpRequest(), cohort: .treatment, token: nil)
        XCTAssertEqual(out?.url?.getParameter(named: "dindexexp"), "b")
    }

    func testSignalledRequest_appendsDindexA_forControl() {
        let out = SerpSearchTokenInterceptor.signalledRequest(for: serpRequest(), cohort: .control, token: nil)
        XCTAssertEqual(out?.url?.getParameter(named: "dindexexp"), "a")
    }

    func testSignalledRequest_nilWhenParamAlreadyPresent() {
        let req = serpRequest("https://duckduckgo.com/?q=privacy&dindexexp=a")
        XCTAssertNil(SerpSearchTokenInterceptor.signalledRequest(for: req, cohort: .control, token: nil))
    }

    func testSignalledRequest_nilForNonSerpURL() {
        let req = serpRequest("https://duckduckgo.com/about")
        XCTAssertNil(SerpSearchTokenInterceptor.signalledRequest(for: req, cohort: .treatment, token: nil))
    }
    
    // MARK: - signalledRequest: dindextoken param

    func testSignalledRequest_setsTokenParam_forTreatmentWithToken() {
        let out = SerpSearchTokenInterceptor.signalledRequest(for: serpRequest(), cohort: .treatment, token: "abc")
        XCTAssertEqual(out?.url?.getParameter(named: "dindextoken"), "abc")
    }

    func testSignalledRequest_noTokenParam_forControlEvenWithToken() {
        let out = SerpSearchTokenInterceptor.signalledRequest(for: serpRequest(), cohort: .control, token: "abc")
        XCTAssertNil(out?.url?.getParameter(named: "dindextoken"))
    }

    func testSignalledRequest_noTokenParam_forTreatmentWithoutToken() {
        let out = SerpSearchTokenInterceptor.signalledRequest(for: serpRequest(), cohort: .treatment, token: nil)
        XCTAssertEqual(out?.url?.getParameter(named: "dindexexp"), "b")
        XCTAssertNil(out?.url?.getParameter(named: "dindextoken"))
    }

    func testSignalledRequest_nilWhenBothParamsAlreadyPresent() {
        let req = serpRequest("https://duckduckgo.com/?q=privacy&dindexexp=b&dindextoken=abc")
        XCTAssertNil(SerpSearchTokenInterceptor.signalledRequest(for: req, cohort: .treatment, token: "abc"))
    }

    func testSignalledRequest_replacesStaleTokenParam() {
        let req = serpRequest("https://duckduckgo.com/?q=privacy&dindexexp=b&dindextoken=old")
        let out = SerpSearchTokenInterceptor.signalledRequest(for: req, cohort: .treatment, token: "new")
        XCTAssertEqual(out?.url?.getParameter(named: "dindextoken"), "new")
    }
    
    // MARK: - strippingToken

    func testStrippingToken_removesTokenParam() {
        let url = URL(string: "https://duckduckgo.com/?q=privacy&dindexexp=b&dindextoken=abc")!
        let out = SerpSearchTokenInterceptor.strippingToken(from: url)
        XCTAssertNil(out.getParameter(named: "dindextoken"))
        XCTAssertEqual(out.getParameter(named: "q"), "privacy")
        XCTAssertEqual(out.getParameter(named: "dindexexp"), "b")
    }

    func testStrippingToken_noOpWhenAbsent() {
        let url = URL(string: "https://duckduckgo.com/?q=privacy&dindexexp=b")!
        XCTAssertEqual(SerpSearchTokenInterceptor.strippingToken(from: url), url)
    }

    // MARK: - Helpers
    
    private func serpRequest(_ string: String = "https://duckduckgo.com/?q=privacy") -> URLRequest {
        URLRequest(url: URL(string: string)!)
    }
}
