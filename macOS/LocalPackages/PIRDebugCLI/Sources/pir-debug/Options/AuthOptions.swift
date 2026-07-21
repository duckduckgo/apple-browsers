//
//  AuthOptions.swift
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

import ArgumentParser
import DataBrokerProtectionCore
import Foundation
import PIRDebugKit

/// Authentication token used only by the email/captcha services during opt-out. Rules fetch and
/// captcha-free scans need no token.
struct AuthOptions: ParsableArguments {

    static let envVariableName = "PRIVACYPRO_STAGING_ACCESS_TOKEN_V2"

    @Option(name: .long, help: "Staging JWT for email/captcha (opt-out). Falls back to $\(AuthOptions.envVariableName).")
    var authToken: String?

    /// The resolved token: `--auth-token`, else the environment variable, else `nil`.
    var resolvedToken: String? {
        if let authToken, !authToken.isEmpty { return authToken }
        if let env = ProcessInfo.processInfo.environment[Self.envVariableName], !env.isEmpty { return env }
        return nil
    }

    func authenticationManager() -> DataBrokerProtectionAuthenticationManaging {
        StaticTokenAuthenticationManager(token: resolvedToken)
    }
}
