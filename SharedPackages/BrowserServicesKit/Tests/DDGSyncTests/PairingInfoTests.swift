//
//  PairingInfoTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import DDGSync

final class PairingInfoTests: XCTestCase {

    private static let ddgURL = URL(string: "https://duckduckgo.com")!

// MARK: init

    func testInit_replacesHyphensWithPluses() throws {
        assertURLFrom(
            inputString: "https://duckduckgo.com/sync/pairing/#&code=-eyJyZWNvdmVyeSI6-eyJ1c2VyX2lkIjoiQjM4MDJGN-DUtMkExMC00MUIzLUI1QUEtM--zcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9fQ&deviceName=My%20iPhone",
            resultsIn: "+eyJyZWNvdmVyeSI6+eyJ1c2VyX2lkIjoiQjM4MDJGN+DUtMkExMC00MUIzLUI1QUEtM++zcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9fQ="
        )
    }

    func testInit_replacesUnderscoresWithForwardslashes() throws {
        assertURLFrom(
            inputString: "https://duckduckgo.com/sync/pairing/#&code=_eyJyZWNvdmVyeSI6eyJ1c2VyX2lk_IjoiQjM4MDJGNDUtMkExMC_00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SD__B3MDdsQ0ZDTlFTZERVPSJ9fQ&deviceName=My%20iPhone",
            resultsIn: "/eyJyZWNvdmVyeSI6eyJ1c2VyX2lk/IjoiQjM4MDJGNDUtMkExMC/00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SD//B3MDdsQ0ZDTlFTZERVPSJ9fQ="
        )
    }

    func testInit_addsPadding() throws {
        assertURLFrom(
            inputString: "https://duckduckgo.com/sync/pairing/#&code=eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiQjM4MDJGNDUtMkExMC00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9fQd&deviceName=My%20iPhone",
            resultsIn: "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiQjM4MDJGNDUtMkExMC00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9fQd="
        )

        assertURLFrom(
            inputString: "https://duckduckgo.com/sync/pairing/#&code=eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiQjM4MDJGNDUtMkExMC00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9f&deviceName=My%20iPhone",
            resultsIn: "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiQjM4MDJGNDUtMkExMC00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9f==="
        )
    }

    private func assertURLFrom(inputString: String, resultsIn base64Code: String, file: StaticString = #file, line: UInt = #line) {
        let input = URL(string: inputString)!
        guard let pairingInfo = PairingInfo(url: input) else {
            XCTFail("Failed to init with url \(input)", file: file, line: line)
            return
        }

        XCTAssertEqual(pairingInfo.base64Code, base64Code, file: file, line: line)
    }

    func testInit_parsesDeviceName() {
        for (input, output) in [
            "My%20iPhone": "My iPhone",
            "onewiththenumber42": "onewiththenumber42",
            "ONEMOREFORLUCK": "ONEMOREFORLUCK"
        ] {
            let input = URL(string: "https://duckduckgo.com/sync/pairing/#&code=eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiQjM4MDJGNDUtMkExMC00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9&deviceName=\(input)")!
            guard let pairingInfo = PairingInfo(url: input) else {
                XCTFail("Failed to init with url \(input)")
                return
            }

            XCTAssertEqual(pairingInfo.deviceName, output)
        }
    }

    // MARK: toURL

    func testToURL_replacesPlusesWithHyphens() {
        let pairingInfo = PairingInfo(base64Code: "+ABCDEFGHIJKLMNOPQ+RSTU+VWXYZabcdefghijklmnopqrstuvwxyz0123456789+", deviceName: "")
        XCTAssertEqual(pairingInfo.toURL(baseURL: Self.ddgURL).absoluteString, "https://duckduckgo.com/sync/pairing/#&code=-ABCDEFGHIJKLMNOPQ-RSTU-VWXYZabcdefghijklmnopqrstuvwxyz0123456789-&deviceName=")
    }

    func testToURL_replacesForwardslashesWithUnderscores() {
        let pairingInfo = PairingInfo(base64Code: "/ABCDE/FGHIJKLMNOPQRSTUVWXYZabcdef/ghijklmnopqrstuvwxyz0123456789/", deviceName: "")
        XCTAssertEqual(pairingInfo.toURL(baseURL: Self.ddgURL).absoluteString, "https://duckduckgo.com/sync/pairing/#&code=_ABCDE_FGHIJKLMNOPQRSTUVWXYZabcdef_ghijklmnopqrstuvwxyz0123456789_&deviceName=")
    }

    func testToURL_removesPadding() {
        let pairingInfo = PairingInfo(base64Code: "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiQjM4MDJGNDUtMkExMC00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9====", deviceName: "")
        XCTAssertEqual(pairingInfo.toURL(baseURL: Self.ddgURL).absoluteString, "https://duckduckgo.com/sync/pairing/#&code=eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiQjM4MDJGNDUtMkExMC00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9&deviceName=")
    }

    func testToURL_addsDeviceName() {
        for (input, output) in [
            "My iPhone": "My%2520iPhone",
            "onewiththenumber42": "onewiththenumber42",
            "ONEMOREFORLUCK": "ONEMOREFORLUCK"
        ] {
            let pairingInfo = PairingInfo(base64Code: "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiQjM4MDJGNDUtMkExMC00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9", deviceName: input)
            XCTAssertEqual(pairingInfo.toURL(baseURL: Self.ddgURL).absoluteString, "https://duckduckgo.com/sync/pairing/#&code=eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiQjM4MDJGNDUtMkExMC00MUIzLUI1QUEtMzcwQjU3NDMwMTE0IiwicHJpbWFyeV9rZXkiOiIzbHl3U1dsZWxZeW01bWdSbHl2Z0NqN3JsQW90SDB3MDdsQ0ZDTlFTZERVPSJ9&deviceName=\(output)"
            )
        }
    }
}
