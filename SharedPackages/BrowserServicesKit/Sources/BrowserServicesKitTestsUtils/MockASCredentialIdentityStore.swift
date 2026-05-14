//
//  MockASCredentialIdentityStore.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import AuthenticationServices
@testable import BrowserServicesKit

final class MockASCredentialIdentityStore: ASCredentialIdentityStoring {
    var isEnabled = true
    var supportsIncrementalUpdates = true
    var savedPasswordCredentialIdentities: [ASPasswordCredentialIdentity] = []
    var error: Error?

    // Using this computed property to handle iOS 17 availability for ASCredentialIdentity
    private var _savedCredentialIdentities: [Any] = []

    func state() async -> ASCredentialIdentityStoreState {
        return MockASCredentialIdentityStoreState(isEnabled: isEnabled, supportsIncrementalUpdates: supportsIncrementalUpdates)
    }

    func saveCredentialIdentities(_ credentials: [ASPasswordCredentialIdentity]) async throws {
        if let error = error {
            throw error
        }

        for credential in credentials {
            if let index = savedPasswordCredentialIdentities.firstIndex(where: { $0.recordIdentifier == credential.recordIdentifier }) {
                savedPasswordCredentialIdentities[index] = credential
            } else {
                savedPasswordCredentialIdentities.append(credential)
            }
        }
    }

    func removeCredentialIdentities(_ credentials: [ASPasswordCredentialIdentity]) async throws {
        if let error = error {
            throw error
        }
        let identifiersToRemove = Set(credentials.map { $0.recordIdentifier })
        savedPasswordCredentialIdentities.removeAll { identifiersToRemove.contains($0.recordIdentifier) }
    }

    func replaceCredentialIdentities(with newCredentials: [ASPasswordCredentialIdentity]) async throws {
        if let error = error {
            throw error
        }
        savedPasswordCredentialIdentities = newCredentials
    }

}

@available(iOS 17.0, macOS 14.0, *)
extension MockASCredentialIdentityStore {

    var savedCredentialIdentities: [ASCredentialIdentity] {
        get {
            return _savedCredentialIdentities as? [ASCredentialIdentity] ?? []
        }
        set {
            _savedCredentialIdentities = newValue
        }
    }

    func saveCredentialIdentities(_ credentials: [ASCredentialIdentity]) async throws {
        if let error = error {
            throw error
        }
        for credential in credentials {
            if let index = savedCredentialIdentities.firstIndex(where: { $0.recordIdentifier == credential.recordIdentifier }) {
                savedCredentialIdentities[index] = credential
            } else {
                savedCredentialIdentities.append(credential)
            }
        }
    }

    func removeCredentialIdentities(_ credentials: [ASCredentialIdentity]) async throws {
        if let error = error {
            throw error
        }
        let identifiersToRemove = Set(credentials.map { $0.recordIdentifier })
        savedCredentialIdentities.removeAll { identifiersToRemove.contains($0.recordIdentifier) }
    }

    func replaceCredentialIdentities(_ newCredentials: [ASCredentialIdentity]) async throws {
        if let error = error {
            throw error
        }
        savedCredentialIdentities = newCredentials
    }
}

private class MockASCredentialIdentityStoreState: ASCredentialIdentityStoreState {
    private var _isEnabled: Bool
    private var _supportsIncrementalUpdates: Bool

    override var isEnabled: Bool {
        return _isEnabled
    }

    override var supportsIncrementalUpdates: Bool {
        return _supportsIncrementalUpdates
    }

    init(isEnabled: Bool, supportsIncrementalUpdates: Bool) {
        self._isEnabled = isEnabled
        self._supportsIncrementalUpdates = supportsIncrementalUpdates
        super.init()
    }
}
