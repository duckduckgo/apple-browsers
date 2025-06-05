//
//  MockLoginItemsManager.swift
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

import LoginItems
@testable import DuckDuckGo_Privacy_Browser

struct MockLoginItemsManager: LoginItemsManaging {

    typealias LoginItemsCallback = (Set<LoginItems.LoginItem>) -> Void
    typealias ThrowsLoginItemsCallback = (Set<LoginItems.LoginItem>) throws -> Void

    private let enableLoginItemsCallback: LoginItemsCallback
    private let throwingEnableLoginItemsCallback: ThrowsLoginItemsCallback
    private let disableLoginItemsCallback: LoginItemsCallback
    private let restartLoginItemsCallback: LoginItemsCallback
    private let isAnyEnabledCallback: (Set<LoginItems.LoginItem>) -> Bool

    init(enableLoginItemsCallback: @escaping LoginItemsCallback = { _ in },
         throwingEnableLoginItemsCallback: @escaping ThrowsLoginItemsCallback = { _ in },
         disableLoginItemsCallback: @escaping LoginItemsCallback = { _ in },
         restartLoginItemsCallback: @escaping LoginItemsCallback = { _ in },
         isAnyEnabledCallback: @escaping (Set<LoginItems.LoginItem>) -> Bool) {

        self.enableLoginItemsCallback = enableLoginItemsCallback
        self.throwingEnableLoginItemsCallback = throwingEnableLoginItemsCallback
        self.disableLoginItemsCallback = disableLoginItemsCallback
        self.restartLoginItemsCallback = restartLoginItemsCallback
        self.isAnyEnabledCallback = isAnyEnabledCallback
    }

    func enableLoginItems(_ items: Set<LoginItems.LoginItem>) {
        enableLoginItemsCallback(items)
    }

    func throwingEnableLoginItems(_ items: Set<LoginItems.LoginItem>) throws {
        try throwingEnableLoginItemsCallback(items)
    }

    func disableLoginItems(_ items: Set<LoginItems.LoginItem>) {
        disableLoginItemsCallback(items)
    }

    func restartLoginItems(_ items: Set<LoginItems.LoginItem>) {
        restartLoginItemsCallback(items)
    }

    func isAnyEnabled(_ items: Set<LoginItems.LoginItem>) -> Bool {
        isAnyEnabledCallback(items)
    }
}
