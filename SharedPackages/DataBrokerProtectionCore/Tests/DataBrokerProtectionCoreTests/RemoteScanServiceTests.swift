//
//  RemoteScanServiceTests.swift
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
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class RemoteScanServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var settings: DataBrokerProtectionSettings!

    override func setUp() {
        super.setUp()
        let suiteName = "RemoteScanServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = DataBrokerProtectionSettings(defaults: defaults)
    }

    // MARK: - URL building

    func testDefaultBaseURLIsLocalhost() throws {
        let service = RemoteScanService(settings: settings)

        XCTAssertEqual(try service.url(forScanId: nil).absoluteString, "http://localhost:8080/v0/scans")
        XCTAssertEqual(try service.url(forScanId: "abc-123").absoluteString, "http://localhost:8080/v0/scans/abc-123")
    }

    func testCustomBaseURLWithPathAndTrailingSlash() throws {
        settings.remoteJobServerURLString = "https://pir.example.com/api/"
        let service = RemoteScanService(settings: settings)

        XCTAssertEqual(try service.url(forScanId: nil).absoluteString, "https://pir.example.com/api/v0/scans")
        XCTAssertEqual(try service.url(forScanId: "abc").absoluteString, "https://pir.example.com/api/v0/scans/abc")
    }

    func testInvalidOverrideFallsBackToDefault() {
        settings.remoteJobServerURLString = "not a url"
        XCTAssertEqual(settings.remoteJobServerURL, DataBrokerProtectionSettings.defaultRemoteJobServerURL)

        settings.remoteJobServerURLString = "   "
        XCTAssertEqual(settings.remoteJobServerURL, DataBrokerProtectionSettings.defaultRemoteJobServerURL)
    }

    // MARK: - Decoding the match schema

    func testDecodesStatusResponseWithFullMatchSchema() throws {
        let json = """
        {
          "scanId": "5a1d",
          "status": "completed",
          "matches": [
            {
              "name": "John V Smith",
              "alternativeNames": ["John Vsmith"],
              "age": "38",
              "addresses": [
                { "city": "Chicago", "state": "IL", "extras": { "street": "123 Main St", "zip": "60601" } },
                { "city": "Naperville", "state": "IL" }
              ],
              "phoneNumbers": ["3125550100"],
              "relatives": ["Cheryl Lamar"],
              "profileUrl": "https://www.spokeo.com/John-Smith/p123",
              "identifier": "p123",
              "extras": { "shoeSize": "10.5" }
            },
            {
              "name": "Jon Smith",
              "alternativeNames": [],
              "age": null,
              "addresses": [],
              "phoneNumbers": [],
              "relatives": [],
              "profileUrl": "https://www.spokeo.com/Jon-Smith/p999"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(RemoteScanStatusResponse.self, from: json)

        XCTAssertEqual(response.scanId, "5a1d")
        XCTAssertEqual(response.status, .completed)
        XCTAssertNil(response.error)

        let matches = try XCTUnwrap(response.matches)
        XCTAssertEqual(matches.count, 2)

        let first = matches[0]
        XCTAssertEqual(first.name, "John V Smith")
        XCTAssertEqual(first.alternativeNames, ["John Vsmith"])
        XCTAssertEqual(first.age, "38")
        XCTAssertEqual(first.addresses?.count, 2)
        XCTAssertEqual(first.addresses?.first?.city, "Chicago")
        XCTAssertEqual(first.addresses?.first?.extras?["zip"], "60601")
        XCTAssertNil(first.addresses?.last?.extras)
        XCTAssertEqual(first.phoneNumbers, ["3125550100"])
        XCTAssertEqual(first.relatives, ["Cheryl Lamar"])
        XCTAssertEqual(first.profileUrl, "https://www.spokeo.com/John-Smith/p123")
        XCTAssertEqual(first.identifier, "p123")
        XCTAssertEqual(first.extras?["shoeSize"], "10.5")
        XCTAssertNil(first.id)
        XCTAssertNil(first.removedDate)

        // identifier falls back to profileUrl when the server omits it, matching the webview path.
        let second = matches[1]
        XCTAssertNil(second.age)
        XCTAssertEqual(second.identifier, "https://www.spokeo.com/Jon-Smith/p999")
    }

    func testDecodesFailedStatus() throws {
        let json = """
        { "scanId": "x", "status": "failed", "error": { "message": "captcha unsolved" } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteScanStatusResponse.self, from: json)

        XCTAssertEqual(response.status, .failed)
        XCTAssertNil(response.matches)
        XCTAssertEqual(response.error, RemoteScanError(message: "captcha unsolved"))
    }

    func testEncodesRequestWithoutOptionalNils() throws {
        let request = RemoteScanRequest(brokerId: "spokeo.com.json",
                                        profile: RemoteScanProfile(profileQuery: .mock))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]

        XCTAssertEqual(json?["brokerId"] as? String, "spokeo.com.json")
        let profile = try XCTUnwrap(json?["profile"] as? [String: Any])
        XCTAssertEqual(profile["firstName"] as? String, "First")
        XCTAssertEqual(profile["birthYear"] as? Int, 1980)
        XCTAssertFalse(profile.keys.contains("middleName"))
        XCTAssertFalse(profile.keys.contains("suffix"))
    }
}
