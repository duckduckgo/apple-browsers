//
//  DataImportWideEventDataTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import PixelKit
@testable import BrowserServicesKit

final class DataImportWideEventDataTests: XCTestCase {

    func testPixelParameters_setupWithCompleteSuccessfulFlow() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "test-context")
        )

        let base = Date()
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.5)
        )
        eventData.bookmarkImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )
        eventData.passwordImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )
        eventData.creditCardImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )

        eventData.bookmarkImportStatus = .success
        eventData.passwordImportStatus = .success
        eventData.creditCardImportStatus = .success

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.name"], "data-import")
        XCTAssertEqual(parameters["feature.data.ext.source"], "safari")

        // Have all per type status
        for type in DataImport.DataType.allCases {
            XCTAssertEqual(parameters["feature.data.ext.\(type.description)_status"], "SUCCESS")
            XCTAssertNil(parameters["feature.data.ext.passwords_status_reason"])
        }

        // Have all per type durations
        XCTAssertEqual(parameters["feature.data.ext.latency_ms"], "1500")
        for type in DataImport.DataType.allCases {
            XCTAssertEqual(parameters["feature.data.ext.\(type.description)_importer_latency_ms"], "1000")
        }

        // No per type errors
        for type in DataImport.DataType.allCases {
            XCTAssertNil(parameters["feature.data.ext.\(type.description)_error.domain"])
            XCTAssertNil(parameters["feature.data.ext.\(type.description)_error.code"])
            XCTAssertNil(parameters["feature.data.ext.\(type.description)_error.code"])
        }
    }

    func testPixelParameters_setupWithPartialSuccessfulFlow() {
        let eventData = DataImportWideEventData(
            source: .chrome,
            contextData: WideEventContextData(name: "test-context")
        )

        let base = Date()
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.5)
        )
        eventData.bookmarkImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )
        eventData.passwordImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )
        eventData.creditCardImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )

        eventData.bookmarkImportStatus = .success(reason: DataImportWideEventData.StatusReason.partialData.rawValue)
        eventData.passwordImportStatus = .failure
        eventData.creditCardImportStatus = .unknown(reason: DataImportWideEventData.StatusReason.partialData.rawValue)

        let passwordImportError = NSError(domain: "DataImportError", code: 1, userInfo: nil)
        eventData.passwordImportError = WideEventErrorData(error: passwordImportError, description: "no data")

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.name"], "data-import")
        XCTAssertEqual(parameters["feature.data.ext.source"], "chrome")

        // Have all per type status
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_status"], "SUCCESS")
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_status_reason"], "partial_data")

        XCTAssertEqual(parameters["feature.data.ext.passwords_status"], "FAILURE")
        XCTAssertNil(parameters["feature.data.ext.passwords_status_reason"])

        XCTAssertEqual(parameters["feature.data.ext.creditCards_status"], "UNKNOWN")
        XCTAssertEqual(parameters["feature.data.ext.creditCards_status_reason"], "partial_data")

        // Have all per type durations
        XCTAssertEqual(parameters["feature.data.ext.latency_ms"], "1500")
        for type in DataImport.DataType.allCases {
            XCTAssertEqual(parameters["feature.data.ext.\(type.description)_importer_latency_ms"], "1000")
        }

        // Have per type error
        XCTAssertNil(parameters["feature.data.ext.bookmarks_error.domain"])
        XCTAssertEqual(parameters["feature.data.ext.passwords_error.domain"], "DataImportError")
        XCTAssertEqual(parameters["feature.data.ext.passwords_error.code"], "1")
        XCTAssertEqual(parameters["feature.data.ext.passwords_error.description"], "no data")
        XCTAssertNil(parameters["feature.data.ext.creditCards_error.domain"])
    }

    func testPixelParameters_setupWithFailedFlow() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "test-context")
        )

        let base = Date()
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.5)
        )
        eventData.bookmarkImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )

        eventData.bookmarkImportStatus = .failure

        let bookmarkImportError = NSError(domain: "DataImportError", code: 1, userInfo: nil)
        eventData.bookmarkImportError = WideEventErrorData(error: bookmarkImportError, description: "no data")

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.name"], "data-import")
        XCTAssertEqual(parameters["feature.data.ext.source"], "safari")

        // Have all per type status
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_status"], "FAILURE")
        XCTAssertNil(parameters["feature.data.ext.bookmarks_status_reason"])

        // Have all per type durations
        XCTAssertEqual(parameters["feature.data.ext.latency_ms"], "1500")
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_importer_latency_ms"], "1000")
        XCTAssertNil(parameters["feature.data.ext.passwords_importer_latency_ms"])
        XCTAssertNil(parameters["feature.data.ext.creditCards_importer_latency_ms"])

        // Have per type error
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.domain"], "DataImportError")
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.code"], "1")
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.description"], "no data")
        XCTAssertNil(parameters["feature.data.ext.passwords_error.domain"])
        XCTAssertNil(parameters["feature.data.ext.creditCards_error.domain"])

    }

    // MARK: - Abandoned and Delayed Flows

    func testPixelParameters_withAbandonedFlows() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()
        // no start interval
        var parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.latency_ms"])

        // has ended interval
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base, end: base.addingTimeInterval(2.5)
        )
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.latency_ms"], "2500")
    }

    func testPixelParameters_withDelayedFlows() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "test-context")
        )
        let base = Date()

        // start only
        eventData.overallDuration  = WideEvent.MeasuredInterval(start: base, end: nil)
        var parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.latency_ms"])

        // end only
        eventData.overallDuration = WideEvent.MeasuredInterval(start: nil, end: base)
        parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.latency_ms"])
    }

    // MARK: - addTypeStatusAndReason

    func testAddTypeStatusAndReason_withValidData() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )
        eventData.bookmarkImportStatus = .success
        eventData.passwordImportStatus = .unknown(reason: DataImportWideEventData.StatusReason.partialData.rawValue)
        eventData.creditCardImportStatus = .failure

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_status"], "SUCCESS")
        XCTAssertNil(parameters["feature.data.ext.bookmarks_status_reason"])

        XCTAssertEqual(parameters["feature.data.ext.passwords_status"], "UNKNOWN")
        XCTAssertEqual(parameters["feature.data.ext.passwords_status_reason"], "partial_data")

        XCTAssertEqual(parameters["feature.data.ext.creditCards_status"], "FAILURE")
        XCTAssertNil(parameters["feature.data.ext.creditCards_status_reason"])
    }

    func testAddTypeStatusAndReason_withNil() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )
        let parameters = eventData.pixelParameters()
        for type in DataImport.DataType.allCases {
            XCTAssertNil(parameters["feature.data.ext.\(type.description)_status"])
        }
    }

    // MARK: - addTypeImporterLatency

    func testAddTypeImporterLatency_withValidIntervalData() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let base = Date()
        eventData.overallDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.5)
        )
        eventData.bookmarkImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )
        eventData.passwordImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )
        eventData.creditCardImporterDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(1.0)
        )

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.latency_ms"], "1500")
        for type in DataImport.DataType.allCases {
            XCTAssertEqual(parameters["feature.data.ext.\(type.description)_importer_latency_ms"], "1000")
        }
    }

    func testAddTypeImporterLatency_withNilInterval() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let parameters = eventData.pixelParameters()

        // All durations are nil
        for type in DataImport.DataType.allCases {
            XCTAssertNil(parameters["feature.data.ext.\(type.description)_importer_latency_ms"])
        }
    }

    // MARK: - addTypeError

    func testAddTypeError_withNilError() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )

        // All errors are nil
        let parameters = eventData.pixelParameters()
        for type in DataImport.DataType.allCases {
            XCTAssertNil(parameters["feature.data.ext.\(type.description)_error.domain"])
            XCTAssertNil(parameters["feature.data.ext.\(type.description)_error.code"])
            XCTAssertNil(parameters["feature.data.ext.\(type.description)_error.code"])
        }
    }

    func testAddTypeError_withTopLevelError() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let error = NSError(domain: "DataImportError", code: 1, userInfo: nil)
        eventData.passwordImportError = WideEventErrorData(error: error, description: "no data")

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.passwords_error.domain"], "DataImportError")
        XCTAssertEqual(parameters["feature.data.ext.passwords_error.code"], "1")
        XCTAssertEqual(parameters["feature.data.ext.passwords_error.description"], "no data")
    }

    func testAddTypeError_withSingleUnderlyingError() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let underlyingError = NSError(domain: "UnderlyingDomain", code: 100, userInfo: nil)
        let topError = NSError(domain: "TopDomain", code: 200, userInfo: [
            NSUnderlyingErrorKey: underlyingError
        ])
        eventData.bookmarkImportError = WideEventErrorData(error: topError)

        let parameters = eventData.pixelParameters()
        // Top error
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.domain"], "TopDomain")
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.code"], "200")

        // Underlying error: Single Underlying error does not have suffix
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.underlying_domain"], "UnderlyingDomain")
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.underlying_code"], "100")
    }

    func testAddTypeError_withMultipleUnderlyingErrors() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let underlyingError2 = NSError(domain: "Domain2", code: 2, userInfo: [:])
        let underlyingError1 = NSError(domain: "Domain1", code: 1, userInfo: [
            NSUnderlyingErrorKey: underlyingError2
        ])
        let topError = NSError(domain: "TopDomain", code: 0, userInfo: [
            NSUnderlyingErrorKey: underlyingError1
        ])

        eventData.creditCardImportError = WideEventErrorData(error: topError)

        let parameters = eventData.pixelParameters()

        // Top error
        XCTAssertEqual(parameters["feature.data.ext.creditCards_error.domain"], "TopDomain")
        XCTAssertEqual(parameters["feature.data.ext.creditCards_error.code"], "0")

        // First underlying error: First Underlying error does not have suffix
        XCTAssertEqual(parameters["feature.data.ext.creditCards_error.underlying_domain"], "Domain1")
        XCTAssertEqual(parameters["feature.data.ext.creditCards_error.underlying_code"], "1")

        // Second underlying error
        XCTAssertEqual(parameters["feature.data.ext.creditCards_error.underlying_domain2"], "Domain2")
        XCTAssertEqual(parameters["feature.data.ext.creditCards_error.underlying_code2"], "2")
    }

    // MARK: - transformErrorKey

    func testTransformErrorKey() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let error = NSError(domain: "DataImportError", code: 1, userInfo: nil)

        eventData.bookmarkImportError = WideEventErrorData(error: error, description: "no data")
        var parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.domain"], "DataImportError")
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.code"], "1")
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.description"], "no data")

        eventData.passwordImportError = WideEventErrorData(error: error, description: "no data")
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.passwords_error.domain"], "DataImportError")
        XCTAssertEqual(parameters["feature.data.ext.passwords_error.code"], "1")
        XCTAssertEqual(parameters["feature.data.ext.passwords_error.description"], "no data")

        // No Description
        eventData.creditCardImportError = WideEventErrorData(error: error)
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.creditCards_error.domain"], "DataImportError")
        XCTAssertEqual(parameters["feature.data.ext.creditCards_error.code"], "1")
        XCTAssertNil(parameters["feature.data.ext.creditCards_error.description"])
    }

    func testTransformErrorKey_underlyingDomainWithNoSuffix() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )

        let underlyingError = NSError(domain: "UnderlyingDomain", code: 1, userInfo: nil)
        let topError = NSError(domain: "TopDomain", code: 0, userInfo: [
            NSUnderlyingErrorKey: underlyingError
        ])

        eventData.bookmarkImportError = WideEventErrorData(error: topError)
        let parameters = eventData.pixelParameters()
        // Underlying error: Single Underlying error does not have suffix
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.underlying_domain"], "UnderlyingDomain")
        XCTAssertEqual(parameters["feature.data.ext.bookmarks_error.underlying_code"], "1")
    }

    func testTransformErrorKey_underlyingDomainWithSuffix() {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData(name: "Test-Context")
        )

        // Create deep nested underlying errors
        let underlyingError20 = NSError(domain: "Domain20", code: 20, userInfo: nil)
        var currentError = underlyingError20
        for i in (1...19).reversed() {
            currentError = NSError(domain: "Domain\(i)", code: i, userInfo: [
                NSUnderlyingErrorKey: currentError
            ])
        }

        let topError = NSError(domain: "TopDomain", code: 0, userInfo: [
            NSUnderlyingErrorKey: currentError
        ])

        eventData.passwordImportError = WideEventErrorData(error: topError)
        let parameters = eventData.pixelParameters()

        for i in 1...20 {
            if i == 1 {
                XCTAssertEqual(parameters["feature.data.ext.passwords_error.underlying_domain"], "Domain1")
            } else {
                XCTAssertEqual(parameters["feature.data.ext.passwords_error.underlying_domain\(i)"], "Domain\(i)")
            }
        }
    }

    // MARK: - Completion Decision

    func testCompletionDecision_noOverallDurationStart_returnsPartialData() async {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData()
        )

        let decision = await eventData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: DataImportWideEventData.StatusReason.partialData.rawValue))
        case .keepPending:
            XCTFail("Expected completion with partial data")
        }
    }

    func testCompletionDecision_intervalAlreadyCompleted_returnsPartialData() async {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData()
        )
        let start = Date()
        eventData.overallDuration = WideEvent.MeasuredInterval(start: start, end: start.addingTimeInterval(1))

        let decision = await eventData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: DataImportWideEventData.StatusReason.partialData.rawValue))
        case .keepPending:
            XCTFail("Expected completion with partial data")
        }
    }

    func testCompletionDecision_importTimeoutExceeded_returnsTimeout() async {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData()
        )
        let start = Date().addingTimeInterval(-DataImportWideEventData.importTimeout - 1)
        eventData.overallDuration = WideEvent.MeasuredInterval(start: start, end: nil)

        let decision = await eventData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: DataImportWideEventData.StatusReason.timeout.rawValue))
        case .keepPending:
            XCTFail("Expected completion with timeout")
        }
    }

    func testCompletionDecision_withinTimeout_returnsKeepPending() async {
        let eventData = DataImportWideEventData(
            source: .safari,
            contextData: WideEventContextData()
        )
        let start = Date().addingTimeInterval(-DataImportWideEventData.importTimeout + 1)
        eventData.overallDuration = WideEvent.MeasuredInterval(start: start, end: nil)

        let decision = await eventData.completionDecision(for: .appLaunch)

        switch decision {
        case .keepPending:
            break
        case .complete:
            XCTFail("Expected keep pending")
        }
    }
}
