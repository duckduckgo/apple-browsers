//
//  ChromeWebStoreUpdateManifestParserTests.swift
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

import Foundation
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class ChromeWebStoreUpdateManifestParserTests: XCTestCase {
    private let fixture = ChromeWebStoreUpdateManifestFixture()

    private func parse(_ xml: String) throws -> ChromeWebStoreUpdateChecker.Update? {
        try ChromeWebStoreUpdateManifestParser.parse(Data(xml.utf8), extensionID: fixture.extensionID)
    }

    private func assertInvalid(_ data: Data, message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ChromeWebStoreUpdateManifestParser.parse(data, extensionID: fixture.extensionID), message, file: file, line: line) { error in
            XCTAssertEqual(error as? ChromeWebStoreUpdateChecker.Failure, .invalidManifest, message, file: file, line: line)
        }
    }

    func testAvailableUpdateFromRealResponseShape() throws {
        let update = try XCTUnwrap(parse(fixture.manifest(fixture.offer())))
        XCTAssertEqual(update.extensionID, fixture.extensionID)
        XCTAssertEqual(update.version, "2026.10.1")
        XCTAssertEqual(update.size, 26045122)
        XCTAssertEqual(update.sha256, fixture.packageHash)
        XCTAssertEqual(update.downloadURL.absoluteString, "https://clients2.googleusercontent.com/crx/extension.crx")
    }

    func testNoUpdateFromRealResponseShape() throws {
        XCTAssertNil(try parse(fixture.manifest(#"<updatecheck status="noupdate"/>"#)))
    }

    func testInvalidOfferMetadataIsRejected() {
        let valid = fixture.offer()
        let replacements = [
            ("version=\"2026.10.1\"", "version=\"1.0-beta\""),
            ("version=\"2026.10.1\"", "version=\"65536\""),
            ("version=\"2026.10.1\"", ""),
            ("size=\"26045122\"", "size=\"0\""),
            ("size=\"26045122\"", "size=\"-1\""),
            ("size=\"26045122\"", "size=\"99999999999999999999999\""),
            ("size=\"26045122\"", ""),
            ("hash_sha256=\"\(fixture.packageHash)\"", "hash_sha256=\"bad\""),
            ("hash_sha256=\"\(fixture.packageHash)\"", ""),
            ("status=\"ok\"", "status=\"error\""),
            ("status=\"ok\"", "")
        ]
        for (old, new) in replacements {
            assertInvalid(Data(fixture.manifest(valid.replacingOccurrences(of: old, with: new)).utf8), message: new)
        }
    }

    func testDisallowedPackageURLsAreRejected() {
        for url in ["http://clients2.googleusercontent.com/x", "https://evil.example/x",
                    "https://clients2.googleusercontent.com.evil.example/x", "https://user@clients2.googleusercontent.com/x",
                    "https://clients2.googleusercontent.com:444/x", "https://clients2.googleusercontent.com/x#fragment"] {
            let offer = fixture.offer().replacingOccurrences(of: "https://clients2.googleusercontent.com/crx/extension.crx", with: url)
            assertInvalid(Data(fixture.manifest(offer).utf8), message: url)
        }
    }

    func testWrongOrAmbiguousApplicationAndStatusAreRejected() {
        let app = "<app appid=\"\(fixture.extensionID)\" status=\"ok\">\(fixture.offer())</app>"
        let invalid = [
            fixture.manifest(fixture.offer(), appID: String(repeating: "a", count: 32)),
            fixture.manifest(fixture.offer(), appStatus: "error-unknownApplication"),
            fixture.manifest(fixture.offer() + fixture.offer()),
            fixture.manifest(fixture.offer()).replacingOccurrences(of: "</gupdate>", with: app + "</gupdate>"),
            fixture.manifest(fixture.offer()).replacingOccurrences(of: "protocol=\"2.0\"", with: "protocol=\"3.0\""),
            fixture.manifest(fixture.offer()).replacingOccurrences(of: "http://www.google.com/update2/response", with: "https://evil.example"),
            fixture.manifest(fixture.offer()).replacingOccurrences(of: "</gupdate>", with: ""),
            "<gupdate/>", "", "not XML"
        ]
        for xml in invalid {
            assertInvalid(Data(xml.utf8), message: xml)
        }
    }

    func testDTDsAndNonUTF8EncodingsAreRejected() throws {
        let body = fixture.manifest(fixture.offer())
        let declaration = #"<?xml version="1.0" encoding="UTF-8"?>"#
        let dtds = [
            "<!DOCTYPE gupdate>",
            #"<!DOCTYPE gupdate SYSTEM "https://evil.example/external.dtd">"#,
            #"<!DOCTYPE gupdate [<!ENTITY example "expanded">]>"#,
            #"<!DOCTYPE gupdate [<!ENTITY example SYSTEM "file:///etc/passwd">]>"#
        ]
        for dtd in dtds {
            assertInvalid(Data(body.replacingOccurrences(of: declaration, with: declaration + dtd).utf8))
        }
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            assertInvalid(try XCTUnwrap(body.data(using: encoding)))
        }
        assertInvalid(Data(body.replacingOccurrences(of: "UTF-8", with: "ISO-8859-1").utf8))
    }

    func testUTF8BOMAndNamespacePrefixesAreAccepted() throws {
        let xml = fixture.manifest(fixture.offer()).replacingOccurrences(of: "xmlns=", with: "xmlns:g=")
            .replacingOccurrences(of: "<gupdate", with: "<g:gupdate")
            .replacingOccurrences(of: "</gupdate", with: "</g:gupdate")
            .replacingOccurrences(of: "<daystart", with: "<g:daystart")
            .replacingOccurrences(of: "<app", with: "<g:app")
            .replacingOccurrences(of: "</app", with: "</g:app")
            .replacingOccurrences(of: "<updatecheck", with: "<g:updatecheck")
        XCTAssertNotNil(try parse("\u{FEFF}" + xml))
    }

    func testHashIsNormalizedToLowercase() throws {
        let offer = fixture.offer().replacingOccurrences(of: fixture.packageHash, with: fixture.packageHash.uppercased())
        let update = try XCTUnwrap(parse(fixture.manifest(offer)))
        XCTAssertEqual(update.sha256, fixture.packageHash)
    }

    func testUnknownElementsAndUnexpectedNestingAreRejected() {
        let manifest = fixture.manifest(fixture.offer())
        let invalid = [
            manifest.replacingOccurrences(of: "<daystart", with: "<unknown"),
            manifest.replacingOccurrences(of: fixture.offer(), with: "<wrapper>\(fixture.offer())</wrapper>"),
            manifest.replacingOccurrences(of: fixture.offer(), with: "<daystart/>\(fixture.offer())"),
            manifest.replacingOccurrences(of: fixture.offer(), with: "<updatecheck status=\"noupdate\"><daystart/></updatecheck>")
        ]
        for xml in invalid {
            assertInvalid(Data(xml.utf8), message: xml)
        }
    }

    func testElementCountLimit() throws {
        // Root, app and updatecheck contribute three elements; the fixture also contains one daystart.
        let extraElements = String(repeating: "<daystart/>", count: 252)
        let atLimit = fixture.manifest(fixture.offer()).replacingOccurrences(of: "<app ", with: extraElements + "<app ")
        XCTAssertNotNil(try parse(atLimit))
        let overLimit = atLimit.replacingOccurrences(of: "<app ", with: "<daystart/><app ")
        assertInvalid(Data(overLimit.utf8))
    }
}

struct ChromeWebStoreUpdateManifestFixture {
    let extensionID = "nngceckbapebfimnlniiiahkandclblb"
    let packageHash = "d92953eac40d64f5b38e254d2196babb0bf0c5e81c1d9afaae4cd88a55bab42c"

    func manifest(_ update: String, appID: String? = nil, appStatus: String = "ok") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <gupdate xmlns="http://www.google.com/update2/response" protocol="2.0" server="prod">
          <daystart elapsed_days="7242" elapsed_seconds="22482"/>
          <app appid="\(appID ?? extensionID)" status="\(appStatus)">\(update)</app>
        </gupdate>
        """
    }

    func offer(version: String = "2026.10.1") -> String {
        """
        <updatecheck _esbAllowlist="true" codebase="https://clients2.googleusercontent.com/crx/extension.crx"
          fp="1.\(packageHash)" hash_sha256="\(packageHash)" protected="0" size="26045122" status="ok" version="\(version)"/>
        """
    }
}
