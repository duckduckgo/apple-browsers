//
//  BackupRestoreFailureTests.swift
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
@testable import Networking

final class BackupRestoreFailureTests: XCTestCase {

    func testNetworkServerAndReadFailures_areTemporary() {
        XCTAssertEqual(BackupRestoreFailure(URLError(.timedOut)), .temporary)
        XCTAssertEqual(BackupRestoreFailure(APIRequestV2Error.urlSession(URLError(.notConnectedToInternet))), .temporary)
        XCTAssertEqual(BackupRestoreFailure(OAuthServiceError.invalidResponseCode(.internalServerError)), .temporary)
        XCTAssertEqual(BackupRestoreFailure(OAuthServiceError.invalidResponseCode(.requestTimeout)), .temporary)
        XCTAssertEqual(BackupRestoreFailure(OAuthServiceError.invalidResponseCode(.tooManyRequests)), .temporary)
        XCTAssertEqual(BackupRestoreFailure(TokenBackupError.readFailed(underlying: NSError(domain: "keychain", code: 1))), .temporary)
    }

    func testRejectedBackupsAndRefreshes_arePermanent() {
        XCTAssertEqual(BackupRestoreFailure(TokenBackupError.unavailable), .permanent)
        XCTAssertEqual(BackupRestoreFailure(TokenBackupError.expired), .permanent)
        XCTAssertEqual(BackupRestoreFailure(TokenBackupError.sessionChanged), .permanent)
        XCTAssertEqual(BackupRestoreFailure(OAuthClientError.invalidTokenRequest(.reused)), .permanent)
        XCTAssertEqual(BackupRestoreFailure(OAuthClientError.unknownAccount), .permanent)
    }

    func testOtherFailures_areUnknown() {
        let suspended = OAuthRequestError(from: OAuthRequest.BodyError(errorCode: .suspendedAccount, tokenStatus: nil))

        XCTAssertEqual(BackupRestoreFailure(OAuthServiceError.authAPIError(suspended)), .unknown)
        XCTAssertEqual(BackupRestoreFailure(OAuthServiceError.invalidResponseCode(.badRequest)), .unknown)
        XCTAssertEqual(BackupRestoreFailure(NSError(domain: "JWT", code: 1)), .unknown)
    }
}
