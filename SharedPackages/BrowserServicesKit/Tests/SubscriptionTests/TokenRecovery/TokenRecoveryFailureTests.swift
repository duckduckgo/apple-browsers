//
//  TokenRecoveryFailureTests.swift
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

final class TokenRecoveryFailureTests: XCTestCase {

    func testWhenBackupIsRejectedThenFailureIsPermanent() {
        XCTAssertEqual(TokenRecoveryFailure(TokenBackupError.expired), .permanent)
        XCTAssertEqual(TokenRecoveryFailure(TokenBackupError.accountMismatch), .permanent)
        XCTAssertEqual(TokenRecoveryFailure(TokenBackupError.predatesSignOut), .permanent)
        XCTAssertEqual(TokenRecoveryFailure(TokenBackupError.undecodable), .permanent)
    }

    func testWhenRefreshIsRejectedThenFailureIsPermanent() {
        XCTAssertEqual(TokenRecoveryFailure(OAuthClientError.invalidTokenRequest(.reused)), .permanent)
    }

    func testWhenAccountIsUnknownThenFailureIsPermanent() {
        XCTAssertEqual(TokenRecoveryFailure(OAuthClientError.unknownAccount), .permanent)
    }

    func testWhenNoAppStorePurchaseThenFailureIsPermanent() {
        XCTAssertEqual(TokenRecoveryFailure(AppStoreRestoreFlowError.missingAccountOrTransactions), .permanent)
    }

    func testWhenAppStoreSubscriptionExpiredThenFailureIsPermanent() {
        XCTAssertEqual(TokenRecoveryFailure(AppStoreRestoreFlowError.subscriptionExpired), .permanent)
    }

    func testWhenOfflineThenFailureIsTemporary() {
        XCTAssertEqual(TokenRecoveryFailure(URLError(.notConnectedToInternet)), .temporary)
    }

    func testWhenServerIsUnavailableThenFailureIsTemporary() {
        XCTAssertEqual(TokenRecoveryFailure(OAuthServiceError.invalidResponseCode(.serviceUnavailable)), .temporary)
    }

    func testWhenKeychainIsLockedThenFailureIsTemporary() {
        let locked = NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInteractionNotAllowed))
        XCTAssertEqual(TokenRecoveryFailure(TokenBackupError.readFailed(underlying: locked)), .temporary)
    }

    func testWhenErrorIsUnknownThenFailureIsTemporary() {
        XCTAssertEqual(TokenRecoveryFailure(NSError(domain: "test", code: 1)), .temporary)
        XCTAssertEqual(TokenRecoveryFailure(AppStoreRestoreFlowError.pastTransactionAuthenticationError), .temporary)
    }
}
