//
//  UnifiedDeviceListEventTests.swift
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

@testable import DDGSync

final class UnifiedDeviceListEventTests: XCTestCase {

    func testDimensionsAreEncodedInPixelParameters() {
        let fallback = UnifiedDeviceListEvent.ownRowResolvedLegacy(.notPublishedYet)
        XCTAssertEqual(fallback.name, "sync_unified_devices_own_row_resolved_legacy")
        XCTAssertEqual(fallback.parameters, ["reason": "not_published_yet"])

        let keyUnavailable = UnifiedDeviceListEvent.accountInfoKeyUnavailable(.noWrapForOurCredential)
        XCTAssertEqual(keyUnavailable.name, "sync_unified_devices_account_info_key_unavailable")
        XCTAssertEqual(keyUnavailable.parameters, ["reason": "no_wrap_for_our_credential"])

        let invalidKeyMaterial = UnifiedDeviceListEvent.accountInfoKeyUnavailable(.invalidKeyMaterial)
        XCTAssertEqual(invalidKeyMaterial.parameters, ["reason": "invalid_key_material"])

        let otherRow = UnifiedDeviceListEvent.otherRowDeviceInfoFailedDecryption(.thirdParty)
        XCTAssertEqual(otherRow.parameters, ["credential": "3party"])

        let writeFailure = UnifiedDeviceListEvent.ownRowDeviceInfoRepairFailed(.encryptFailed)
        XCTAssertEqual(writeFailure.name, "sync_unified_devices_own_row_device_info_repair_failed")
        XCTAssertEqual(writeFailure.parameters, ["reason": "encrypt_failed"])

        let persistenceFailure = UnifiedDeviceListEvent.ownRowDeviceInfoUpdateFailed(.persistFailed)
        XCTAssertEqual(persistenceFailure.parameters, ["reason": "persist_failed"])
    }

    func testReadEventsAreDaily() {
        XCTAssertEqual(UnifiedDeviceListEvent.ownRowResolvedDeviceInfo.frequency, .daily)
        XCTAssertEqual(UnifiedDeviceListEvent.ownRowResolvedPlaceholder(.blobDecryptFailed).frequency, .daily)
    }

    func testParameterizedEventsAreDailyByName() {
        let events: [UnifiedDeviceListEvent] = [
            .ownRowResolvedLegacy(.notPublishedYet),
            .ownRowResolvedPlaceholder(.blobDecryptFailed),
            .accountInfoKeyUnavailable(.noKeyOnServer),
            .otherRowDeviceInfoFailedDecryption(.thirdParty),
            .otherRowResolvedPlaceholder(.none),
            .accountInfoKeyAdoptFailed(.keysFetchFailed),
            .accountInfoKeyCreateFailed(.mintFailed),
            .accountInfoKeyWrapFailed(.unwrapFailed),
            .ownRowDeviceInfoFirstWriteFailed(.encryptFailed),
            .ownRowDeviceInfoUpdateFailed(.requestFailed),
            .ownRowDeviceInfoRepairFailed(.rateLimited)
        ]

        for event in events {
            XCTAssertEqual(event.frequency, .daily, event.name)
        }
    }

    func testSuccessEventsAreStandardAndFailureEventsAreDaily() {
        XCTAssertEqual(UnifiedDeviceListEvent.accountInfoKeyCreateSuccess.frequency, .standard)
        XCTAssertEqual(UnifiedDeviceListEvent.ownRowDeviceInfoUpdateSuccess.frequency, .standard)
        XCTAssertEqual(UnifiedDeviceListEvent.accountInfoKeyAdoptFailed(.rateLimited).frequency, .daily)
        XCTAssertEqual(UnifiedDeviceListEvent.ownRowDeviceInfoFirstWriteFailed(.encryptFailed).frequency, .daily)
    }

    func testAccountInfoKeyUnavailableClassifiesFetchAndUnwrapFailuresSeparately() {
        XCTAssertEqual(
            UnifiedDeviceListTelemetry.accountInfoKeyUnavailableReason(for: URLError(.timedOut)),
            .keysFetchFailed)
        XCTAssertEqual(
            UnifiedDeviceListTelemetry.accountInfoKeyUnavailableReason(for: SyncError.failedToDecryptValue("test")),
            .unwrapFailed)
    }
}
