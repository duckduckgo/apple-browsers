//
//  TLDTests.swift
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
@testable import Common

final class TLDTests: XCTestCase {

    let tld = TLD()

    func testWhenJsonAccessedThenReturnsValidJson() {
        let tlds = try? JSONDecoder().decode([String].self, from: tld.json.data(using: .utf8)!)

        XCTAssertNotNil(tlds)
        XCTAssertFalse(tlds?.isEmpty ?? true)
    }

    func testWhenHostMultiPartTopLevelWithSubdomainThenDomainCorrect() {
        XCTAssertEqual("bbc.co.uk", tld.domain("www.bbc.co.uk"))
        XCTAssertEqual("bbc.co.uk", tld.domain("other.bbc.co.uk"))
        XCTAssertEqual("bbc.co.uk", tld.domain("multi.part.bbc.co.uk"))
    }

    func testWhenHostDotComWithSubdomainThenDomainIsTopLevel() {
        XCTAssertEqual("example.com", tld.domain("www.example.com"))
        XCTAssertEqual("example.com", tld.domain("other.example.com"))
        XCTAssertEqual("example.com", tld.domain("multi.part.example.com"))
    }

    func testWhenHostIsTopLevelDotComThenDomainIsSame() {
        XCTAssertEqual("example.com", tld.domain("example.com"))
    }

    func testWhenHostIsMalformedThenDomainIsFixed() {
        XCTAssertEqual("example.com", tld.domain(".example.com"))
    }

    func testWhenHostMultiPartTopLevelWithSubdomainThenETLDp1Correct() {
        XCTAssertEqual("bbc.co.uk", tld.eTLDplus1("www.bbc.co.uk"))
        XCTAssertEqual("bbc.co.uk", tld.eTLDplus1("other.bbc.co.uk"))
        XCTAssertEqual("bbc.co.uk", tld.eTLDplus1("multi.part.bbc.co.uk"))
    }

    func testWhenHostDotComWithSubdomainThenETLDp1Correct() {
        XCTAssertEqual("example.com", tld.eTLDplus1("www.example.com"))
        XCTAssertEqual("example.com", tld.eTLDplus1("other.example.com"))
        XCTAssertEqual("example.com", tld.eTLDplus1("multi.part.example.com"))
    }

    func testWhenHostIsTLDLevelThenETLDp1IsNotFound() {
        XCTAssertEqual(nil, tld.eTLDplus1("com"))
        XCTAssertEqual(nil, tld.eTLDplus1("co.uk"))
    }

    func testWhenHostIsIncorrectThenETLDp1IsNotFound() {
        XCTAssertEqual(nil, tld.eTLDplus1("abcderfg"))
    }

    func testWhenHostIsNilDomainIsNil() {
        XCTAssertNil(tld.domain(nil))
    }

    func testWhenHostIsTLDThenDomainIsFound() {
        XCTAssertEqual("com", tld.domain("com"))
        XCTAssertEqual("co.uk", tld.domain("co.uk"))
    }

    func testWhenHostIsMultiPartTLDThenDomainIsFound() {
        XCTAssertEqual(nil, tld.domain("za"))
        XCTAssertEqual("co.za", tld.domain("co.za"))
    }

    func testWhenHostIsIncorrectThenDomainIsNil() {
        XCTAssertNil(tld.domain("abcdefgh"))
    }

    func testWhenTLDInstantiatedThenLoadsTLDData() {
        XCTAssertFalse(tld.tlds.isEmpty)
    }

    func testWhenTLDIsExampleThenItIsMatched() {
        XCTAssertEqual("something.example", tld.domain("something.example"))
        XCTAssertEqual("example", tld.domain("example"))
    }

    func testWhenStringURLHasNoSubdomainThenSecondLevelDomainCorrect() {
        XCTAssertEqual("example", tld.extractSecondLevelDomain(fromStringURL: "https://example.com"))
        XCTAssertEqual("bbc", tld.extractSecondLevelDomain(fromStringURL: "https://bbc.co.uk"))
    }

    func testWhenStringURLMultiPartTopLevelWithSubdomainThenSecondLevelDomainCorrect() {
        XCTAssertEqual("bbc", tld.extractSecondLevelDomain(fromStringURL: "https://www.bbc.co.uk"))
        XCTAssertEqual("bbc", tld.extractSecondLevelDomain(fromStringURL: "https://other.bbc.co.uk"))
        XCTAssertEqual("bbc", tld.extractSecondLevelDomain(fromStringURL: "https://multi.part.bbc.co.uk"))
    }

    func testWhenStringURLDotComWithSubdomainThenSecondLevelDomainCorrect() {
        XCTAssertEqual("example", tld.extractSecondLevelDomain(fromStringURL: "https://www.example.com"))
        XCTAssertEqual("example", tld.extractSecondLevelDomain(fromStringURL: "https://other.example.com"))
        XCTAssertEqual("example", tld.extractSecondLevelDomain(fromStringURL: "https://multi.part.example.com"))
    }

    func testWhenStringURLIsTLDLevelThenSecondLevelDomainIsNotFound() {
        XCTAssertEqual(nil, tld.extractSecondLevelDomain(fromStringURL: "https://com"))
        XCTAssertEqual(nil, tld.extractSecondLevelDomain(fromStringURL: "https://co.uk"))
    }

    func testWhenStringURLIsIncorrectThenSecondLevelDomainIsNotFound() {
        XCTAssertEqual(nil, tld.extractSecondLevelDomain(fromStringURL: "https://abcderfg"))
    }

    // MARK: - eTLD Tests

    func testWhenHostMultiPartTopLevelWithSubdomainThenETLDCorrect() {
        XCTAssertEqual("co.uk", tld.eTLD("www.bbc.co.uk"))
        XCTAssertEqual("co.uk", tld.eTLD("other.bbc.co.uk"))
        XCTAssertEqual("co.uk", tld.eTLD("multi.part.bbc.co.uk"))
    }

    func testWhenHostDotComWithSubdomainThenETLDCorrect() {
        XCTAssertEqual("com", tld.eTLD("www.example.com"))
        XCTAssertEqual("com", tld.eTLD("other.example.com"))
        XCTAssertEqual("com", tld.eTLD("multi.part.example.com"))
    }

    func testWhenHostIsTopLevelDotComThenETLDIsSame() {
        XCTAssertEqual("com", tld.eTLD("example.com"))
    }

    func testWhenHostIsMalformedThenETLDIsFixed() {
        XCTAssertEqual("com", tld.eTLD(".example.com"))
    }

    func testWhenHostIsTLDThenETLDIsFound() {
        XCTAssertEqual("com", tld.eTLD("com"))
        XCTAssertEqual("co.uk", tld.eTLD("co.uk"))
    }

    func testWhenHostIsMultiPartTLDThenETLDIsFound() {
        XCTAssertEqual(nil, tld.eTLD("za"))
        XCTAssertEqual("co.za", tld.eTLD("co.za"))
    }

    func testWhenHostIsIncorrectThenETLDIsNil() {
        XCTAssertNil(tld.eTLD("abcdefgh"))
    }

    func testWhenHostIsNilThenETLDIsNil() {
        XCTAssertNil(tld.eTLD(nil))
    }

    func testWhenHostIsExampleThenETLDIsFound() {
        XCTAssertEqual("example", tld.eTLD("something.example"))
        XCTAssertEqual("example", tld.eTLD("example"))
    }

    func testWhenHostHasComplexMultiPartTLDThenETLDCorrect() {
        // Test cases with multi-part TLDs
        XCTAssertEqual("edu.au", tld.eTLD("university.edu.au"))
        XCTAssertEqual("gov.uk", tld.eTLD("department.gov.uk"))
        XCTAssertEqual("ac.uk", tld.eTLD("subdomain.university.ac.uk"))
    }

    func testWhenHostHasPortThenETLDIgnoresPort() {
        // The eTLD function should work with hosts that might have ports
        XCTAssertEqual("com", tld.eTLD("example.com:8080"))
        XCTAssertEqual("co.uk", tld.eTLD("bbc.co.uk:443"))
    }

}
