//
//  SettingsDictionary.swift
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

/// Turns a JSON literal into the `[String: Any]` shape remote config hands EventHub, so tests can keep
/// expressing settings as readable JSON. Traps on invalid JSON: that is a broken test fixture, not a
/// scenario under test — malformed config bytes can no longer reach EventHub, since BSK parses them.
func settingsDictionary(_ json: String) -> [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
          let dictionary = object as? [String: Any] else {
        fatalError("invalid settings JSON in test fixture: \(json)")
    }
    return dictionary
}
