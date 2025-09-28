//
//  WideEventData.swift
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
import Common

public protocol WideEventData: Codable, WideEventParameterProviding {
    static var pixelName: String { get }

    /// Data about the context that the event was sent in, such as the parent feature that the event is operating in.
    /// For example, the context name for a data import event could be the flow that triggered the import, such as onboarding.
    var contextData: WideEventContextData { get set }

    /// Data sent with all wide events, such as sample rate and event type.
    var globalData: WideEventGlobalData { get set }

    /// Data about the current install of the app, such as version and form factor.
    var appData: WideEventAppData { get set }
}

public enum WideEventStatus: Codable, Equatable, CustomStringConvertible {
    case success(reason: String? = nil)
    case failure
    case cancelled
    case unknown(reason: String)

    public static var success: WideEventStatus {
        return .success(reason: nil)
    }

    public var description: String {
        switch self {
        case .success: return "SUCCESS"
        case .failure: return "FAILURE"
        case .cancelled: return "CANCELLED"
        case .unknown: return "UNKNOWN"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case reason
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .type)

        if case let .success(reason) = self {
            try container.encode(reason, forKey: .reason)
        }

        if case let .unknown(reason) = self {
            try container.encode(reason, forKey: .reason)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "SUCCESS":
            let reason = (try? container.decode(String.self, forKey: .reason)) ?? nil
            self = .success(reason: reason)
        case "FAILURE": self = .failure
        case "CANCELLED": self = .cancelled
        case "UNKNOWN":
            let reason = (try? container.decode(String.self, forKey: .reason)) ?? ""
            self = .unknown(reason: reason)
        default:
            self = .unknown(reason: type)
        }
    }
}

// MARK: - WideEventGlobalData

public struct WideEventGlobalData: Codable {
    /// Used for storing event data locally; not included in the event payload.
    public let id: String

    /// The platform that the event is being sent from, e.g. iOS.
    public var platform: String

    /// The type of event data
    /// - Note: For Apple clients, this will always be set to `app`.
    public let type: String

    /// The sample rate used to determine whether to send the event, between 0 and 1.
    public var sampleRate: Float

    public init() {
        self.init(sampleRate: 1.0)
    }

    public init(id: String = UUID().uuidString, platform: String = DevicePlatform.currentPlatform.rawValue, sampleRate: Float) {
        if sampleRate > 1.0 || sampleRate < 0.0 {
            assertionFailure("Sample rate must be between 0-1")
        }

        self.id = id
        self.platform = platform
        self.type = "app" // Don't allow type to be overridden
        self.sampleRate = sampleRate.clamped(to: 0...1)
    }
}

extension WideEventGlobalData: WideEventParameterProviding {
    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WideEventParameter.Global.platform] = platform
        parameters[WideEventParameter.Global.type] = type
        parameters[WideEventParameter.Global.sampleRate] = String(sampleRate)

        return parameters
    }
}

// MARK: - WideEventAppData

public struct WideEventAppData: Codable {
    /// The bundle name of the app sending the event data.
    public var name: String

    /// The bundle version of the app sending the event data.
    public var version: String

    /// The form factor of the device sending the event data.
    /// - Note: This value is only set for mobile devices, to a value of either `phone` or `tablet`.
    public var formFactor: String?

    /// Whether the event was sent by an instance of the app with the internal flag set.
    public var internalUser: Bool?

    public init(name: String = AppVersion.shared.name,
                version: String = AppVersion.shared.versionNumber,
                formFactor: String? = nil,
                internalUser: Bool? = nil) {
        self.name = name
        self.version = version

        #if os(iOS)
        self.formFactor = formFactor ?? DevicePlatform.formFactor
        #else
        self.formFactor = formFactor // Ignore the form factor on macOS, but allow it to be overridden for testing
        #endif
        self.internalUser = internalUser
    }
}

extension WideEventAppData: WideEventParameterProviding {

    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WideEventParameter.App.name] = name
        parameters[WideEventParameter.App.version] = version

        if let formFactor = formFactor {
            parameters[WideEventParameter.Global.formFactor] = formFactor
        }

        if let internalUser {
            parameters[WideEventParameter.App.internalUser] = internalUser ? "true" : nil
        }

        return parameters
    }

}

// MARK: - WideEventContextData

public struct WideEventContextData: Codable {

    public var name: String?

    public init(name: String? = nil) {
        self.name = name
    }

}

extension WideEventContextData: WideEventParameterProviding {

    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]
        if let name = name { parameters[WideEventParameter.Context.name] = name }
        return parameters
    }

}

public struct WideEventErrorData: Codable {

    public var domain: String
    public var code: Int
    public var underlyingDomain: String?
    public var underlyingCode: Int?

    public init(error: Error) {
        let nsError = error as NSError
        self.domain = nsError.domain
        self.code = nsError.code

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            self.underlyingDomain = underlyingError.domain
            self.underlyingCode = underlyingError.code
        }
    }

}
