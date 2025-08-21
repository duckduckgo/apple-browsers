//
//  SyncDeviceButtonModel.swift
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

import Combine
import Persistence
import AppKit
import DDGSync

@MainActor
public final class SyncDeviceButtonModel: ObservableObject {
    @Published var shouldShowSyncButton: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    init(authStatePublisher: AnyPublisher<SyncAuthState, Never>) {
        authStatePublisher
            .map { $0 == .inactive }
            .assign(to: \.shouldShowSyncButton, onWeaklyHeld: self)
            .store(in: &cancellables)
    }
}

extension SyncDeviceButtonModel {
    convenience init() {
        let authStatePublisher: AnyPublisher<SyncAuthState, Never>
        if let syncService = NSApp.delegateTyped.syncService {
            authStatePublisher = syncService.authStatePublisher
        } else {
            authStatePublisher = Just<SyncAuthState>(.initializing).eraseToAnyPublisher()
        }
        self.init(authStatePublisher: authStatePublisher)
    }
}
