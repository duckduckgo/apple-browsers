//
//  CrashCollectionTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

@testable import Crashes
import MetricKit
import XCTest
import Persistence
import PersistenceTestingUtils
import Common

class CrashCollectionTests: XCTestCase {

    func testFirstCrashFlagSent() {
        let crashReportSender = CrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: MockKeyValueStore())
        // 2 pixels with first = true attached
        XCTAssertTrue(crashCollection.isFirstCrash)
        crashCollection.start { pixelParameters, _, _ in
            let firstFlags = pixelParameters.compactMap { $0["first"] }
            XCTAssertFalse(firstFlags.isEmpty)
        }
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])
        XCTAssertFalse(crashCollection.isFirstCrash)
    }

    func testSubsequentPixelsDontSendFirstFlag() {
        let crashReportSender = CrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: MockKeyValueStore())
        // 2 pixels with no first parameter
        crashCollection.isFirstCrash = false
        crashCollection.start { pixelParameters, _, _ in
            let firstFlags = pixelParameters.compactMap { $0["first"] }
            XCTAssertTrue(firstFlags.isEmpty)
        }
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])
        XCTAssertFalse(crashCollection.isFirstCrash)
    }

    func testCRCIDIsStoredWhenReceived() {
        let responseCRCIDValue = "CRCID Value"

        let store = MockKeyValueStore()
        let crashReportSender = MockCrashReportSender(platform: .iOS, pixelEvents: nil)
        crashReportSender.responseCRCID = responseCRCIDValue
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: store)
        let expectation = self.expectation(description: "Crash collection response")

        // Set up closures on our CrashCollection object
        crashCollection.start(process: {_ in
            return ["fake-crash-data".data(using: .utf8)!]  // Not relevant to this test
        }) { pixelParameters, payloads, uploadReports in
            uploadReports()
        } didFinishHandlingResponse: {
            expectation.fulfill()
        }

        // Execute crash collection (which will call our mocked CrashReportSender as well)
        XCTAssertNil(store.object(forKey: CRCIDManager.crcidKey), "CRCID should not be present in the store before crashHandler receives crashes")
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])

        self.wait(for: [expectation], timeout: 3)

        XCTAssertEqual(store.object(forKey: CRCIDManager.crcidKey) as? String, responseCRCIDValue)
    }

    func testCRCIDIsClearedWhenServerReturnsSuccessWithNoCRCID()
    {
        let store = MockKeyValueStore()
        let crashReportSender = MockCrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: store)
        let expectation = self.expectation(description: "Crash collection response")

        // Set up closures on our CrashCollection object
        crashCollection.start(process: {_ in
            return ["fake-crash-data".data(using: .utf8)!]  // Not relevant to this test
        }) { pixelParameters, payloads, uploadReports in
            uploadReports()
        } didFinishHandlingResponse: {
            expectation.fulfill()
        }

        // Execute crash collection (which will call our mocked CrashReportSender as well)
        store.set("Initial CRCID Value", forKey: CRCIDManager.crcidKey)
        XCTAssertNotNil(store.object(forKey: CRCIDManager.crcidKey))
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])

        self.wait(for: [expectation], timeout: 3)

        XCTAssertEqual(store.object(forKey: CRCIDManager.crcidKey) as! String, "", "CRCID should not be present in the store after receiving a successful response")
    }

    func testCRCIDIsRetainedWhenServerErrorIsReceived() {
        let store = MockKeyValueStore()
        let crashReportSender = MockCrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: store)
        let expectation = self.expectation(description: "Crash collection response")

        // Set up closures on our CrashCollection object
        crashCollection.start(process: {_ in
            return ["fake-crash-data".data(using: .utf8)!]  // Not relevant to this test
        }) { pixelParameters, payloads, uploadReports in
            uploadReports()
        } didFinishHandlingResponse: {
            expectation.fulfill()
        }

        // Execute crash collection (which will call our mocked CrashReportSender as well)
        let crcid = "Initial CRCID Value"
        store.set(crcid, forKey: CRCIDManager.crcidKey)
        crashReportSender.responseStatusCode = 500
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])

        self.wait(for: [expectation], timeout: 3)

        XCTAssertEqual(store.object(forKey: CRCIDManager.crcidKey) as? String, crcid)
    }
}

class MockPayload: MXDiagnosticPayload {

    var mockCrashes: [MXCrashDiagnostic]?

    init(mockCrashes: [MXCrashDiagnostic]?) {
        self.mockCrashes = mockCrashes
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var crashDiagnostics: [MXCrashDiagnostic]? {
        return mockCrashes
    }
}

class MockCrashReportSender: CrashReportSending {

    let platform: CrashCollectionPlatform
    var responseCRCID: String?
    var responseStatusCode = 200

    var pixelEvents: EventMapping<CrashReportSenderError>?

    required init(platform: CrashCollectionPlatform, pixelEvents: EventMapping<CrashReportSenderError>?) {
        self.platform = platform
    }

    func send(_ crashReportData: Data, crcid: String?, completion: @escaping (_ result: Result<Data?, Error>, _ response: HTTPURLResponse?) -> Void) {
        var responseHeaderFields: [String: String] = [:]
        if let responseCRCID {
            responseHeaderFields[CrashReportSender.httpHeaderCRCID] = responseCRCID
        }

        guard let response = HTTPURLResponse(url: URL(string: "fakeURL")!,
                                             statusCode: responseStatusCode,
                                             httpVersion: nil,
                                             headerFields: responseHeaderFields) else {
            XCTFail("Failed to create HTTPURLResponse")
            return
        }

        if responseStatusCode == 200 {
            completion(.success(nil), response) // Success with nil data
        } else {
            completion(.failure(CrashReportSenderError.submissionFailed(response)), response)
        }
    }

    func send(_ crashReportData: Data, crcid: String?) async -> (result: Result<Data?, Error>, response: HTTPURLResponse?) {
        await withCheckedContinuation { continuation in
            send(crashReportData, crcid: crcid) { result, response in
                continuation.resume(returning: (result, response))
            }
        }
    }
}
