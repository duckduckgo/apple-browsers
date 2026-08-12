//
//  EventHubStoredPixelState.swift
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

/// The serialised, persisted form of a single pixel's runtime state. The repository keeps a map of
/// these (keyed by pixel name) under one composite key in the key-value store. Mirrors the fields
/// Android/Windows persist per row: the period window, the params JSON, and a config-snapshot JSON.
public struct EventHubStoredPixelState: Codable, Equatable, Sendable {
    public let periodStartMillis: Int64
    public let periodEndMillis: Int64
    public let paramsJSON: String
    public let configJSON: String

    public init(periodStartMillis: Int64, periodEndMillis: Int64, paramsJSON: String, configJSON: String) {
        self.periodStartMillis = periodStartMillis
        self.periodEndMillis = periodEndMillis
        self.paramsJSON = paramsJSON
        self.configJSON = configJSON
    }
}
