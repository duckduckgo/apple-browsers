//
//  MockExperimentActionPixelStore.swift
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

import PixelExperimentKit

final class MockExperimentActionPixelStore: ExperimentActionPixelStore {
    var store: [String: Int] = [:]
    func removeObject(forKey defaultName: String) { store.removeValue(forKey: defaultName) }
    func integer(forKey defaultName: String) -> Int { store[defaultName] ?? 0 }
    func set(_ value: Int, forKey defaultName: String) { store[defaultName] = value }
}
