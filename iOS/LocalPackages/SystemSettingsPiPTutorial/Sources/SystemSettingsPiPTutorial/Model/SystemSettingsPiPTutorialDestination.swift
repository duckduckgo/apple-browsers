//
//  SystemSettingsPiPTutorialDestination.swift
//  DuckDuckGo
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

import Foundation
import class UIKit.UIApplication

/// Represents a specific use-case destination within system settings that can display PiP tutorial content.
public struct SystemSettingsPiPTutorialDestination: Sendable, Equatable {

    struct ID: Hashable, Sendable {
        let value: String

        fileprivate init(_ value: String) {
            self.value = value
        }
    }

    let identifier: ID
    let url: URL

    /// Creates a new destination for PiP tutorials.
    ///
    /// - Parameters:
    ///   - identifier: A string identifier that uniquely identifies this destination within system settings.
    ///   - url: The URL where to navigate when the PiP is displayed.
    public init(identifier: String, url: URL) {
        self.identifier = ID(identifier)
        self.url = url
    }
}
