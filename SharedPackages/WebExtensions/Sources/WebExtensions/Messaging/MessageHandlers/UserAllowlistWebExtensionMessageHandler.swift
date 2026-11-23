//
//  UserAllowlistWebExtensionMessageHandler.swift
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
import FoundationExtensions
import os.log
import PrivacyConfig

/// The user's allowlist (sites where the user turned protections off) and a version that identifies its contents.
///
/// The version is derived from the contents, so it needs no storage and is the same across launches for the same
/// list. The extension sends the version it holds, and gets the list back only when the versions differ.
public struct UserAllowlistSnapshot: Equatable {

    public let domains: [String]
    public let version: String

    public init(domains: [String]) {
        let sorted = Array(Set(domains)).sorted()
        self.domains = sorted
        self.version = sorted.joined(separator: "\n").sha256
    }
}

/// Answers the embedded extension's `userAllowlist` messages.
///
/// The extension pulls the list when its background starts. Later changes reach it as subscription events (see
/// `WebExtensionManager.installUserAllowlistNotifier(privacyConfigurationManager:)`).
@available(macOS 15.4, iOS 18.4, *)
public final class UserAllowlistWebExtensionMessageHandler: WebExtensionMessageHandler {

    enum Method: String {
        case getAllowlistIfNew
    }

    private let allowlist: () -> [String]

    public var handledFeatureName: String { UserAllowlistSync.featureName }

    /// - Parameter allowlist: The domains the user has turned protections off for, such as
    ///   `privacyConfigurationManager.privacyConfig.userUnprotectedDomains`.
    public init(allowlist: @escaping () -> [String]) {
        self.allowlist = allowlist
    }

    /// Answers with `privacyConfigurationManager.privacyConfig.userUnprotectedDomains`.
    public convenience init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.init(allowlist: { [privacyConfigurationManager] in privacyConfigurationManager.privacyConfig.userUnprotectedDomains })
    }

    public func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        guard let method = Method(rawValue: message.method) else {
            return .failure(WebExtensionMessageHandlerError.unknownMethod(message.method))
        }
        switch method {
        case .getAllowlistIfNew:
            return allowlistIfNew(knownVersion: message.params?["version"] as? String)
        }
    }

    private func allowlistIfNew(knownVersion: String?) -> WebExtensionMessageResult {
        let snapshot = UserAllowlistSnapshot(domains: allowlist())
        guard snapshot.version != knownVersion else {
            return .success(["updated": false])
        }
        Logger.webExtensions.debug("🛡️ Sending user allowlist (\(snapshot.domains.count, privacy: .public) domains)")
        return .success([
            "updated": true,
            "version": snapshot.version,
            "domains": snapshot.domains,
        ])
    }
}
