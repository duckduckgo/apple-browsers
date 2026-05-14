//
//  AutomationServerError.swift
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

public enum AutomationServerError: Error {
    case noWindow
    case invalidWindowHandle
    case tabNotFound
    case jsonEncodingFailed
    case unsupportedOSVersion
    case unknownMethod
    case invalidURL
    case scriptExecutionFailed
    case screenshotFailed
    case timeout
    case methodNotAllowed
    case unauthorized
    case requestTooLarge
    case invalidPort
}
