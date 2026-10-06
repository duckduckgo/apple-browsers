//
//  SERPInstallOriginUserScript.swift
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
import UserScript
import WebKit

public final class SERPInstallOriginUserScript: NSObject, Subfeature {

    public enum MessageName: String, CaseIterable {
        case handshake
        case getInstallOriginVariant
    }

    public enum DataModel {
        public enum Platform: String, Codable {
            case ios, macos
        }

        public struct HandshakeResponse: Encodable, Equatable {
            public let platform: Platform
            public let installOrigin: Bool

            public init(platform: Platform, installOrigin: Bool) {
                self.platform = platform
                self.installOrigin = installOrigin
            }
        }
    }

    public let featureName: String = "serp"

    public let messageOriginPolicy: MessageOriginPolicy

    public weak var broker: UserScriptMessageBroker?

    private let handler: SERPInstallOriginUserScriptHandling

    public init(serpBaseURL: URL,
                installOriginEnabled: Bool,
                installOriginVariantProvider: InstallOriginVariantProviding?) {
        self.messageOriginPolicy = Self.makeMessageOriginPolicy(for: serpBaseURL)
        self.handler = SERPInstallOriginUserScriptHandler(
            installOriginEnabled: installOriginEnabled,
            installOriginVariantProvider: installOriginVariantProvider
        )
        super.init()
    }

    init(handler: SERPInstallOriginUserScriptHandling, serpBaseURL: URL = URL(string: "https://duckduckgo.com")!) {
        self.messageOriginPolicy = Self.makeMessageOriginPolicy(for: serpBaseURL)
        self.handler = handler
        super.init()
    }

    private static func makeMessageOriginPolicy(for serpBaseURL: URL) -> MessageOriginPolicy {
        let rule = HostnameMatchingRule.makeExactRule(for: serpBaseURL)
            ?? .exact(hostname: "duckduckgo.com")
        return .only(rules: [rule])
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = MessageName(rawValue: methodName) else {
            return { _, _ in throw SERPBridgeError.messageNotImplemented }
        }

        switch message {
        case .handshake:
            return handler.handshake
        case .getInstallOriginVariant:
            return handler.getInstallOriginVariant
        }
    }
}
