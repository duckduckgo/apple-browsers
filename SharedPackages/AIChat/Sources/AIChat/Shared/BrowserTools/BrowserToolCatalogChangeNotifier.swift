//
//  BrowserToolCatalogChangeNotifier.swift
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

/// Fires `onChange` when the set of enabled tools differs from the last one seen. The signature is
/// captured at init, so a publisher that replays on subscribe does not announce a change that
/// never happened.
@MainActor
public final class BrowserToolCatalogChangeNotifier {

    private var lastSignature: [String]
    private let signature: @MainActor () -> [String]
    private let onChange: @MainActor () -> Void
    private var cancellable: AnyCancellable?

    public init(changes: AnyPublisher<Void, Never>,
                signature: @escaping @MainActor () -> [String],
                onChange: @escaping @MainActor () -> Void) {
        self.signature = signature
        self.onChange = onChange
        self.lastSignature = signature()
        cancellable = changes.sink { [weak self] in
            Task { @MainActor in self?.evaluate() }
        }
    }

    private func evaluate() {
        let next = signature()
        guard next != lastSignature else { return }
        lastSignature = next
        onChange()
    }
}
