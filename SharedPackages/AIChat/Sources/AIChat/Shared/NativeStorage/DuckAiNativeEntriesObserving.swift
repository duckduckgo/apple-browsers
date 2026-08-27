//
//  DuckAiNativeEntriesObserving.swift
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

/// Reserved keys only: the entries namespace is web's `localStorage`, so publishing every key would
/// fire on unrelated writes on every page load. Emits whoever wrote it, native writes included.
public protocol DuckAiNativeEntriesObserving {
    /// No initial value: subscribers already read on activation.
    var reservedEntryUpdatesPublisher: AnyPublisher<DuckAiNativeStorageReservedEntryKeys, Never> { get }
}
