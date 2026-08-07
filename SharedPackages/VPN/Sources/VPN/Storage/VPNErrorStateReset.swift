//
//  VPNErrorStateReset.swift
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

import Foundation

/// A store holding the last VPN error message.
protocol LastErrorMessageStoring: AnyObject {
    var lastErrorMessage: String? { get set }
}

/// A store holding the last typed VPN known failure.
protocol LastKnownFailureStoring: AnyObject {
    var lastKnownFailure: KnownFailure? { get set }
}

extension NetworkProtectionTunnelErrorStore: LastErrorMessageStoring {}
extension NetworkProtectionKnownFailureStore: LastKnownFailureStoring {}

/// Clears the two stores holding VPN error signals (last error message and known failure).
///
/// A working connection invalidates both; leaving either set resurfaces on the next disconnect,
/// when the app re-reads the last error.
struct VPNErrorStateReset {

    private let errorMessageStore: LastErrorMessageStoring
    private let knownFailureStore: LastKnownFailureStoring

    init(errorMessageStore: LastErrorMessageStoring,
         knownFailureStore: LastKnownFailureStoring) {
        self.errorMessageStore = errorMessageStore
        self.knownFailureStore = knownFailureStore
    }

    /// Call when the connection is confirmed working, or on a manual start.
    func clear() {
        errorMessageStore.lastErrorMessage = nil
        knownFailureStore.lastKnownFailure = nil
    }
}
