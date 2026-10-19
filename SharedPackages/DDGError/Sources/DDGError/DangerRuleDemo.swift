//
//  DangerRuleDemo.swift
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

// Demo for the ddgErrorConformance Danger rule. This PR will be discarded.

// Should warn: plain Error.
enum DangerDemoPlainError: Error {
    case failed
}

// Should warn: LocalizedError and CustomNSError without DDGError.
public struct DangerDemoLocalizedError: LocalizedError, CustomNSError {
    public var errorDescription: String? { "Demo" }
}

// Should not warn: conforms to DDGError.
enum DangerDemoCompliantError: DDGError {
    case failed

    static var errorDomain: String { "com.duckduckgo.dangerDemo" }
    var errorCode: Int { 1 }
    var underlyingError: Error? { nil }
    var description: String { "Demo failure" }
}

// Should not warn: declared with plain Error, adopts DDGError in an extension.
enum DangerDemoExtensionError: Error {
    case failed
}

extension DangerDemoExtensionError: DDGError {
    static var errorDomain: String { "com.duckduckgo.dangerDemo.extension" }
    var errorCode: Int { 1 }
    var underlyingError: Error? { nil }
    var description: String { "Demo failure" }
}
