//
//  RemoteBrokerProfileScanSubJobRunnerTests.swift
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

final class RemoteBrokerProfileScanSubJobRunnerTests: XCTestCase {

    private var service: MockRemoteScanService!
    private var context: BrokerProfileQueryData!
    private var sleeps: [TimeInterval] = []

    override func setUp() {
        super.setUp()
        service = MockRemoteScanService()
        context = BrokerProfileQueryData.mock(dataBrokerName: "Spokeo", url: "spokeo.com")
        sleeps = []
    }

    private func makeRunner() -> RemoteBrokerProfileScanSubJobRunner {
        RemoteBrokerProfileScanSubJobRunner(service: service,
                                            context: context,
                                            pollInterval: 3,
                                            sleep: { [weak self] interval in self?.sleeps.append(interval) })
    }

    private func status(_ status: RemoteScanStatus,
                        matches: [ExtractedProfile]? = nil,
                        error: RemoteScanError? = nil) -> RemoteScanStatusResponse {
        RemoteScanStatusResponse(scanId: service.scanId, status: status, matches: matches, error: error)
    }

    func testSubmitsBrokerFileIdAndSlimProfile() async throws {
        service.statusResponses = [status(.completed, matches: [])]

        _ = try await makeRunner().scan(showWebView: false, shouldRunNextStep: { true })

        XCTAssertEqual(service.submittedRequests.count, 1)
        let request = try XCTUnwrap(service.submittedRequests.first)
        XCTAssertEqual(request.brokerId, "spokeo.com.json")
        let profileQuery = context.profileQuery
        XCTAssertEqual(request.profile, RemoteScanProfile(profileQuery: profileQuery))
        XCTAssertEqual(request.profile.firstName, profileQuery.firstName)
        XCTAssertEqual(request.profile.middleName, profileQuery.middleName)
        XCTAssertEqual(request.profile.lastName, profileQuery.lastName)
        XCTAssertEqual(request.profile.suffix, profileQuery.suffix)
        XCTAssertEqual(request.profile.city, profileQuery.city)
        XCTAssertEqual(request.profile.state, profileQuery.state)
        XCTAssertEqual(request.profile.birthYear, profileQuery.birthYear)

        // Derived/local fields must not leak into the wire payload.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        let profile = try XCTUnwrap(json?["profile"] as? [String: Any])
        let expectedKeys = Set(["firstName", "lastName", "city", "state", "birthYear"])
            .union(profileQuery.middleName == nil ? [] : ["middleName"])
            .union(profileQuery.suffix == nil ? [] : ["suffix"])
        XCTAssertEqual(Set(profile.keys), expectedKeys)
        XCTAssertNil(profile["age"])
        XCTAssertNil(profile["id"])
    }

    func testPollsUntilCompletedAndReturnsMatches() async throws {
        let match = ExtractedProfile.mockWithName("First Last", age: "46", addresses: [AddressCityState(city: "City", state: "State")])
        service.statusResponses = [status(.queued), status(.running), status(.completed, matches: [match])]

        let result = try await makeRunner().scan(showWebView: false, shouldRunNextStep: { true })

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "First Last")
        XCTAssertEqual(service.statusCallCount, 3)
        XCTAssertEqual(sleeps, [3, 3])
    }

    func testCompletedWithNoMatchesReturnsEmptyArray() async throws {
        service.statusResponses = [status(.completed, matches: nil)]

        let result = try await makeRunner().scan(showWebView: false, shouldRunNextStep: { true })

        XCTAssertTrue(result.isEmpty)
    }

    func testFailedStatusThrowsActionFailed() async {
        service.statusResponses = [status(.failed, error: RemoteScanError(message: "broker blocked us"))]

        do {
            _ = try await makeRunner().scan(showWebView: false, shouldRunNextStep: { true })
            XCTFail("Expected an error")
        } catch let error as DataBrokerProtectionError {
            XCTAssertEqual(error, .actionFailed(actionID: "remoteScan", message: "broker blocked us"))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testCancellationBetweenPollsThrowsCancelled() async {
        service.statusResponses = [status(.queued), status(.queued), status(.completed, matches: [])]
        var calls = 0
        let shouldRunNextStep: () -> Bool = {
            calls += 1
            return calls <= 2 // allow submit + first poll, then cancel
        }

        do {
            _ = try await makeRunner().scan(showWebView: false, shouldRunNextStep: shouldRunNextStep)
            XCTFail("Expected an error")
        } catch let error as DataBrokerProtectionError {
            XCTAssertEqual(error, .cancelled)
            XCTAssertEqual(service.statusCallCount, 1)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testCancellationBeforeSubmitDoesNotSubmit() async {
        do {
            _ = try await makeRunner().scan(showWebView: false, shouldRunNextStep: { false })
            XCTFail("Expected an error")
        } catch let error as DataBrokerProtectionError {
            XCTAssertEqual(error, .cancelled)
            XCTAssertTrue(service.submittedRequests.isEmpty)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testSubmitErrorPropagates() async {
        service.submitError = DataBrokerProtectionError.httpError(code: 503)

        do {
            _ = try await makeRunner().scan(showWebView: false, shouldRunNextStep: { true })
            XCTFail("Expected an error")
        } catch let error as DataBrokerProtectionError {
            XCTAssertEqual(error, .httpError(code: 503))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}
