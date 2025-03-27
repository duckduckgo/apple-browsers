//
//  EmailManager+SyncSupporting.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import Foundation

extension EmailManager: EmailManagerSyncSupporting {
    public var userDidToggleEmailProtectionPublisher: AnyPublisher<Void, Never> {
        Publishers.Merge(
            NotificationCenter.default.publisher(for: .emailDidSignIn),
            NotificationCenter.default.publisher(for: .emailDidSignOut)
        )
        .filter { [weak self] notification in
            guard let self, let object = notification.object as? EmailManager else {
                return false
            }
            return object !== self
        }
        .map { _ in }
        .eraseToAnyPublisher()
    }

    public func signIn(username: String, token: String) throws {
        try storeToken(token, username: username, cohort: nil)
    }
}
