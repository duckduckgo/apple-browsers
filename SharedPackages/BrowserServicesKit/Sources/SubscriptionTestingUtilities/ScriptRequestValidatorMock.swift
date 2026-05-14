//
//  ScriptRequestValidatorMock.swift
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
import WebKit
@testable import Subscription

/// Mock implementation of `ScriptRequestValidator` for testing purposes.
/// Allows configuring the validation result and tracking validation attempts.
public final class ScriptRequestValidatorMock: ScriptRequestValidator {

    /// The result to return from `canPageRequestToken`. Defaults to `true`.
    public var canPageRequestTokenResult: Bool = true

    /// Tracks all messages passed to `canPageRequestToken` for verification in tests.
    public var canPageRequestTokenCalls: [WKScriptMessage] = []

    public init() {}

    /// Validates whether a script message is authorized to request a subscription token.
    ///
    /// - Parameter message: The script message to validate
    /// - Returns: The value of `canPageRequestTokenResult`
    @MainActor
    public func canPageRequestToken(_ message: WKScriptMessage) async -> Bool {
        canPageRequestTokenCalls.append(message)
        return canPageRequestTokenResult
    }
}
