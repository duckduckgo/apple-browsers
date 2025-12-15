//
//  Logger+Multiple.swift
//  DuckDuckGo
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
import os.log

public extension Logger {
    static let adAttribution = Logger(subsystem: "AD Attribution", category: "")
    static let lifecycle = Logger(subsystem: "Lifecycle", category: "")
    static let configuration = Logger(subsystem: "Configuration", category: "")
    static let duckPlayer = Logger(subsystem: "DuckPlayer", category: "")
    static let launchSource = Logger(subsystem: "LaunchSource", category: "")
    static let addressBarPicker = Logger(subsystem: "AddressBar Picker", category: "")
}
