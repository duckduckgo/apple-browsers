//
//  MultiTabAttachmentPage.swift
//  DuckDuckGo
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

import Combine
import Foundation

/// Access to an existing tab. Creating this value never loads a tab.
@MainActor
struct MultiTabAttachmentPage {
    /// Keeps a browser controller available until its preparation or submitted message releases it.
    @MainActor
    final class Reservation {
        private var onRelease: (@MainActor () -> Void)?

        init(onRelease: @escaping @MainActor () -> Void) {
            self.onRelease = onRelease
        }

        func release() {
            let action = onRelease
            onRelease = nil
            action?()
        }

        deinit {
            if let onRelease {
                Task { @MainActor in onRelease() }
            }
        }
    }

    struct Identity: Equatable {
        let webView: ObjectIdentifier
        let navigation: UUID
    }

    struct State {
        let identity: Identity
        let url: URL?
        let isLoading: Bool
        let isLoaded: Bool
        let isAttachable: Bool
        var hasTerminatedProcess = false
    }

    let state: () -> State?
    let changes: AnyPublisher<Void, Never>
    let collect: (URL, @escaping @MainActor () -> Bool) async -> MultiTabAttachmentCollectionResult
    var loadIfNeeded: () -> Void = {}
    var processTerminations: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()
}
