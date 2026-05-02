//
//  SystemExtensionManagerTests.swift
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
@testable import SystemExtensionManager

final class SystemExtensionManagerTests: XCTestCase {

    func testActivationStateWhenNoPropertiesThenNotInstalled() {
        let result = SystemExtensionManager.activationState(from: [])

        XCTAssertEqual(result, .notInstalled)
    }

    func testActivationStateWhenPropertyIsEnabledThenEnabled() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: true, isAwaitingUserApproval: false, isUninstalling: false)
        ])

        XCTAssertEqual(result, .enabled)
    }

    func testActivationStateWhenPropertyIsAwaitingUserApprovalThenAwaitingUserApproval() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: false, isAwaitingUserApproval: true, isUninstalling: false)
        ])

        XCTAssertEqual(result, .awaitingUserApproval)
    }

    func testActivationStateWhenPropertyIsUninstallingThenUninstalling() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: true)
        ])

        XCTAssertEqual(result, .uninstalling)
    }

    func testActivationStateWhenPropertyIsNotEnabledAndNotAwaitingApprovalThenDisabled() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: false)
        ])

        XCTAssertEqual(result, .disabled)
    }

    func testActivationStateWhenMultiplePropertiesIncludeEnabledThenEnabledWins() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: true),
            .init(isEnabled: false, isAwaitingUserApproval: true, isUninstalling: false),
            .init(isEnabled: true, isAwaitingUserApproval: false, isUninstalling: false),
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: true),
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: true)
        ])

        XCTAssertEqual(result, .enabled)
    }
}
