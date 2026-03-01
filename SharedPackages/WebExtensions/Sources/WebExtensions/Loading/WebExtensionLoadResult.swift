//
//  WebExtensionLoadResult.swift
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

@available(macOS 15.4, iOS 18.4, *)
public struct WebExtensionLoadResult {
    public let identifier: String
    public let filename: String
    public let displayName: String?
    public let version: String?

    public init(identifier: String, filename: String, displayName: String?, version: String?) {
        self.identifier = identifier
        self.filename = filename
        self.displayName = displayName
        self.version = version
    }
}
