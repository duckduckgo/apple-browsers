//
//  PageSignalsSettings.swift
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

/// `pageSignals` subfeature settings from the Privacy Config.
public struct PageSignalsSettings: Decodable {
    public static let defaultMaxEntries = 20

    let maxEntries: Int?

    /// Max entries per Page Signals list, or the default when missing or not positive.
    public static func maxEntries(from settings: String?) -> Int {
        guard let data = settings?.data(using: .utf8),
              let maxEntries = try? JSONDecoder().decode(Self.self, from: data).maxEntries,
              maxEntries > 0 else {
            return defaultMaxEntries
        }

        return maxEntries
    }
}
