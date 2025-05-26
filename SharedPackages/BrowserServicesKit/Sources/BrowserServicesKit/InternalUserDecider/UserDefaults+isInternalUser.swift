//
//  UserDefaults+isInternalUser.swift
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

import Combine
import Foundation

extension UserDefaults: InternalUserStoring {
    @objc
    public dynamic var isInternalUser: Bool {
        get {
            bool(forKey: #keyPath(isInternalUser))
        }

        set {
            guard newValue != bool(forKey: #keyPath(isInternalUser)) else {
                return
            }

            guard newValue else {
                removeObject(forKey: #keyPath(isInternalUser))
                return
            }

            set(newValue, forKey: #keyPath(isInternalUser))
        }
    }

    var internalUserPublisher: AnyPublisher<Bool, Never> {
        publisher(for: \.isInternalUser).eraseToAnyPublisher()
    }
}
