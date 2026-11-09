//
//  SubscriptionPixelHandlingTests.swift
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
import Networking
@testable import Subscription

final class SubscriptionPixelHandlingTests: XCTestCase {

    func testBackupEventMapping_storageFailure_isReportedWithItsActionAndOperation() {
        let handler = RecordingPixelHandler()
        let storageError = NSError(domain: "keychain", code: 1)

        handler.backupEventMapping().fire(.storageFailed(.restore, .write, storageError))

        XCTAssertEqual(handler.handledPixels, [.backupKeychainError(.restore, .write, storageError)])
    }

    func testBackupEventMapping_renewalEvents_areReported() {
        let handler = RecordingPixelHandler()
        let renewalError = URLError(.timedOut)

        handler.backupEventMapping().fire(.backupRenewed)
        handler.backupEventMapping().fire(.backupRenewalFailed(renewalError))

        XCTAssertEqual(handler.handledPixels, [.backupRenewed, .backupRenewalFailed(renewalError)])
    }

    func testBackupKeychainErrorHandler_reportsTheProblemsTheStorageFindsWithoutThrowing() {
        let handler = RecordingPixelHandler()
        let errorHandler = handler.backupKeychainErrorHandler()

        errorHandler(.getAuthToken, .failedToDecodeKeychainData)
        errorHandler(.getAuthToken, .expectedTokenNotFound)

        XCTAssertEqual(handler.handledPixels, [.backupKeychainError(nil, .read, AccountKeychainAccessError.failedToDecodeKeychainData),
                                               .backupKeychainError(nil, .read, AccountKeychainAccessError.expectedTokenNotFound)])
    }

    func testBackupKeychainErrorHandler_ignoresTheErrorsTheStorageThrows() {
        let handler = RecordingPixelHandler()
        let errorHandler = handler.backupKeychainErrorHandler()

        errorHandler(.getAuthToken, .keychainLookupFailure(errSecInteractionNotAllowed))
        errorHandler(.storeAuthToken, .keychainSaveFailure(errSecDuplicateItem))
        errorHandler(.storeAuthToken, .keychainDeleteFailure(errSecIO))
        errorHandler(.storeAuthToken, .failedToEncodeKeychainData)

        XCTAssertEqual(handler.handledPixels, [])
    }
}

private final class RecordingPixelHandler: SubscriptionPixelHandling {
    private(set) var handledPixels: [SubscriptionPixelType] = []

    func handle(pixel: SubscriptionPixelType) {
        handledPixels.append(pixel)
    }

    func handle(pixel: KeychainManager.Pixel) {}
}
