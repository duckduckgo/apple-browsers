//
//  UserDefaults+isUsingAuthV2.swift
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
import Foundation

extension UserDefaults {

    @objc
    public dynamic var isUsingAuthV2: Bool {
        get {
            bool(forKey: #keyPath(isUsingAuthV2))
        }

        set {
            guard newValue != bool(forKey: #keyPath(isUsingAuthV2)) else {
                return
            }

            guard newValue else {
                removeObject(forKey: #keyPath(isUsingAuthV2))
                return
            }

            set(newValue, forKey: #keyPath(isUsingAuthV2))
        }
    }

    func resetIsAuthV2Enabled() {
        removeObject(forKey: #keyPath(isUsingAuthV2))
    }
}
