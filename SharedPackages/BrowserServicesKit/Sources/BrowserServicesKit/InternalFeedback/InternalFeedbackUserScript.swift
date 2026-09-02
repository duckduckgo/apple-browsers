//
//  InternalFeedbackUserScript.swift
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

/// Device details reported to the Internal Feedback web app.
///
public struct InternalFeedbackDeviceInfo: Encodable {

    /// App platform token, matching `navigator.duckduckgo.platform` — e.g. "macos".
    public let platform: String
    /// Full app version, e.g. "1.203.0"
    public let appVersion: String
    /// OS display name, e.g. "macOS"
    public let osName: String
    /// Full OS version, e.g. "15.3.1"
    public let osVersion: String

    public let appBuild: String?
    public let formFactor: String?
    public let architecture: String?
    public let locale: String?
    public let channel: String?
    public let deviceModel: String?
    public let deviceManufacturer: String?
    public let diagnostics: [String: String]?

    public init(platform: String,
                appVersion: String,
                osName: String,
                osVersion: String,
                appBuild: String? = nil,
                formFactor: String? = nil,
                architecture: String? = nil,
                locale: String? = nil,
                channel: String? = nil,
                deviceModel: String? = nil,
                deviceManufacturer: String? = nil,
                diagnostics: [String: String]? = nil) {
        self.platform = platform
        self.appVersion = appVersion
        self.osName = osName
        self.osVersion = osVersion
        self.appBuild = appBuild
        self.formFactor = formFactor
        self.architecture = architecture
        self.locale = locale
        self.channel = channel
        self.deviceModel = deviceModel
        self.deviceManufacturer = deviceManufacturer
        self.diagnostics = diagnostics
    }
}

public protocol InternalFeedbackDeviceInfoProviding: AnyObject {
    @MainActor func deviceInfo() -> InternalFeedbackDeviceInfo
}

/// Answers the Internal Feedback web app's requests over the ContentScopeScripts message bridge.
///
public final class InternalFeedbackUserScript: NSObject, Subfeature {

    public enum MessageName: String, CaseIterable {
        case getDeviceInfo
    }

    public static let defaultHostname = "internalapps.duckduckgo.com"

    public let featureName = "internalFeedback"
    public let messageOriginPolicy: MessageOriginPolicy
    public weak var broker: UserScriptMessageBroker?

    private let deviceInfoProvider: InternalFeedbackDeviceInfoProviding

    public init(deviceInfoProvider: InternalFeedbackDeviceInfoProviding,
                hostname: String = InternalFeedbackUserScript.defaultHostname) {
        self.deviceInfoProvider = deviceInfoProvider
        self.messageOriginPolicy = .only(rules: [.exact(hostname: hostname)])
        super.init()
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageName(rawValue: methodName) {
        case .getDeviceInfo:
            return handleGetDeviceInfo
        case .none:
            return nil
        }
    }

    @MainActor
    private func handleGetDeviceInfo(params: Any, message: UserScriptMessage) async throws -> Encodable? {
        deviceInfoProvider.deviceInfo()
    }
}
