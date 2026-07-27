//
//  DBPProfileStateManager.swift
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

import Foundation
import Persistence

public enum DBPProfileState: String {
    case unknown
    case hasProfile
    case noProfile
}

public protocol DBPProfileStateManaging {
    var profileState: DBPProfileState { get }

    func recordProfileSaved()
    func recordProfileDeleted()
    func recordProfileStateUnknown()
    func reconcileProfileState(hasSavedProfile: Bool)
}

public final class DefaultDBPProfileStateManager: DBPProfileStateManaging {

    private enum Keys {
        static let profileState = "ios.browser.dbp.profile.state"
    }

    private let keyValueStore: KeyValueStoring

    public init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    public var profileState: DBPProfileState {
        guard let rawValue = keyValueStore.object(forKey: Keys.profileState) as? String,
              let state = DBPProfileState(rawValue: rawValue) else {
            return .unknown
        }

        return state
    }

    public func recordProfileSaved() {
        setProfileState(.hasProfile)
    }

    public func recordProfileDeleted() {
        setProfileState(.noProfile)
    }

    public func recordProfileStateUnknown() {
        setProfileState(.unknown)
    }

    public func reconcileProfileState(hasSavedProfile: Bool) {
        setProfileState(hasSavedProfile ? .hasProfile : .noProfile)
    }

    private func setProfileState(_ state: DBPProfileState) {
        keyValueStore.set(state.rawValue, forKey: Keys.profileState)
    }

#if DEBUG
    public func setProfileStateForTesting(_ state: DBPProfileState) {
        setProfileState(state)
    }
#endif
}
