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

    func testEventsExposeExpectedPixelContract() {
        let expectations: [(event: UnifiedDeviceListEvent,
                            suffix: String,
                            parameters: [String: String]?,
                            frequency: UnifiedDeviceListEvent.Frequency)] = [
            (.ownRowResolvedDeviceInfo, "own_row_resolved_device_info", nil, .daily),
            (.ownRowResolvedLegacy(.notPublishedYet), "own_row_resolved_legacy", ["reason": "not_published_yet"], .daily),
            (.ownRowResolvedPlaceholder(.blobDecryptFailed), "own_row_resolved_placeholder", ["reason": "blob_decrypt_failed"], .daily),
            (.accountInfoKeyUnavailable(.invalidKeyMaterial), "account_info_key_unavailable", ["reason": "invalid_key_material"], .daily),
            (.otherRowDeviceInfoFailedDecryption(.thirdParty), "other_row_device_info_failed_decryption", ["credential": "3party"], .daily),
            (.otherRowResolvedPlaceholder(.none), "other_row_resolved_placeholder", ["credential": "none"], .daily),
            (.accountInfoKeyAdoptFailed(.keysFetchFailed), "account_info_key_adopt_failed", ["reason": "keys_fetch_failed"], .daily),
            (.accountInfoKeyCreateSuccess, "account_info_key_create_success", nil, .standard),
            (.accountInfoKeyCreateFailed(.mintFailed), "account_info_key_create_failed", ["reason": "mint_failed"], .daily),
            (.accountInfoKeyWrapSuccess, "account_info_key_wrap_success", nil, .standard),
            (.accountInfoKeyWrapFailed(.unwrapFailed), "account_info_key_wrap_failed", ["reason": "unwrap_failed"], .daily),
            (.accountInfoKeyAdoptSuccess, "account_info_key_adopt_success", nil, .standard),
            (.ownRowDeviceInfoFirstWriteSuccess, "own_row_device_info_first_write_success", nil, .standard),
            (.ownRowDeviceInfoFirstWriteFailed(.encryptFailed), "own_row_device_info_first_write_failed", ["reason": "encrypt_failed"], .daily),
            (.ownRowDeviceInfoUpdateSuccess, "own_row_device_info_update_success", nil, .standard),
            (.ownRowDeviceInfoUpdateFailed(.persistFailed), "own_row_device_info_update_failed", ["reason": "persist_failed"], .daily),
            (.ownRowDeviceInfoRepairSuccess, "own_row_device_info_repair_success", nil, .standard),
            (.ownRowDeviceInfoRepairFailed(.rateLimited), "own_row_device_info_repair_failed", ["reason": "rate_limited"], .daily)
        ]

        for expectation in expectations {
            XCTAssertEqual(expectation.event.name, "sync_unified_devices_" + expectation.suffix)
            XCTAssertEqual(expectation.event.parameters, expectation.parameters, expectation.suffix)
            XCTAssertEqual(expectation.event.frequency, expectation.frequency, expectation.suffix)
        }
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
