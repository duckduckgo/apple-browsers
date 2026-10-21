//
//  PasswordManagerCoordinatorTests.swift
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
import BWManagementShared
@testable import DuckDuckGo_Privacy_Browser

final class PasswordManagerCoordinatorTests: XCTestCase {

    func testWhenBitwardenManagementIsNil_ThenIsEnabledReturnsFalse() {
        let coordinator = PasswordManagerCoordinator(bitwardenManagement: nil)

        XCTAssertFalse(coordinator.isEnabled)
    }

    func testWhenBitwardenStatusIsDisabled_ThenIsEnabledReturnsFalse() {
        let manager = MockBitwardenManager()
        manager.status = .disabled
        let coordinator = PasswordManagerCoordinator(bitwardenManagement: manager)

        XCTAssertFalse(coordinator.isEnabled)
    }

    func testWhenBitwardenStatusIsNotDisabled_ThenIsEnabledReturnsTrue() {
        let manager = MockBitwardenManager()
        manager.status = .notInstalled
        let coordinator = PasswordManagerCoordinator(bitwardenManagement: manager)

        XCTAssertTrue(coordinator.isEnabled)
    }

    func testWhenBitwardenStatusIsConnected_ThenIsEnabledReturnsTrue() {
        let manager = MockBitwardenManager()
        let vault = BWVault(id: "id", email: "dax@duck.com", status: .unlocked, active: true)
        manager.status = .connected(vault: vault)
        let coordinator = PasswordManagerCoordinator(bitwardenManagement: manager)

        XCTAssertTrue(coordinator.isEnabled)
    }

}
