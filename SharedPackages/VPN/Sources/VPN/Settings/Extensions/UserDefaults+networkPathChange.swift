//
//  UserDefaults+networkPathChange.swift
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

extension UserDefaults {
    public final class NetworkPathChange: NSObject, Codable {
        public let date: Date
        public let oldPath: String
        public let newPath: String

        public override var description: String {
            "\(oldPath) -> \(newPath)"
        }

        init(date: Date = Date(), oldPath: String, newPath: String) {
            self.date = date
            self.oldPath = oldPath
            self.newPath = newPath
        }
    }

    private var networkPathChangeKey: String {
        "networkPathChange"
    }

    @objc
    public dynamic var networkPathChange: NetworkPathChange? {
        get {
            guard let data = data(forKey: networkPathChangeKey) else { return nil }
            return try? JSONDecoder().decode(NetworkPathChange.self, from: data)
        }

        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            set(data, forKey: networkPathChangeKey)
        }
    }

    public func updateNetworkPath(with newPath: String?) {
        networkPathChange = NetworkPathChange(oldPath: networkPathChange?.newPath ?? "unknown",
                                              newPath: newPath ?? "unknown")
    }
}
