//
//  WidePixelData.swift
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

public protocol WidePixelData: Codable, WidePixelParameterProviding {
    static var pixelName: String { get }

    var contextData: WidePixelContextData { get set }
    var appData: WidePixelAppData { get set }
    var globalData: WidePixelGlobalData { get set }
}

public enum WidePixelStatus: Codable, Equatable, CustomStringConvertible {
    case success(reason: String? = nil)
    case failure
    case cancelled
    case unknown(reason: String)

    public static var success: WidePixelStatus {
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

// MARK: - WidePixelGlobalData

public struct WidePixelGlobalData: Codable {
    public let id: String
    public var platform: String
    public let type: String
    public var sampleRate: Float

    public init() {
        self.init(sampleRate: 1.0)
    }

    public init(platform: String = DevicePlatform.currentPlatform.rawValue, sampleRate: Float) {
        if sampleRate > 1.0 || sampleRate < 0.0 {
            assertionFailure("Sample rate must be between 0-1")
        }

        self.id = UUID().uuidString
        self.platform = platform
        self.type = "app" // Don't allow type to be overridden
        self.sampleRate = sampleRate.clamped(to: 0...1)
    }
}

extension WidePixelGlobalData: WidePixelParameterProviding {
    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WidePixelParameter.Global.platform] = platform
        parameters[WidePixelParameter.Global.type] = type
        parameters[WidePixelParameter.Global.sampleRate] = String(sampleRate)

        return parameters
    }
}

// MARK: - WidePixelAppData

public struct WidePixelAppData: Codable {
    public var name: String
    public var version: String
    public var formFactor: String?
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
        self.formFactor = formFactor // Ignore the form factor on macOS, but allow it to be overriden for testing
        #endif
        self.internalUser = internalUser
    }
}

extension WidePixelAppData: WidePixelParameterProviding {

    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WidePixelParameter.App.name] = name
        parameters[WidePixelParameter.App.version] = version

        if let formFactor = formFactor {
            parameters[WidePixelParameter.Global.formFactor] = formFactor
        }

        if let internalUser {
            parameters[WidePixelParameter.App.internalUser] = internalUser ? "true" : nil
        }

        return parameters
    }

}

// MARK: - WidePixelContextData

public struct WidePixelContextData: Codable {

    public let id: String
    public var name: String?
    public var data: [String: String]?

    public init(id: String = UUID().uuidString, name: String? = nil, data: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.data = data
    }

}

extension WidePixelContextData: WidePixelParameterProviding {

    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        if let name = name { parameters[WidePixelParameter.Context.name] = name }
        if let data = data {
            for (key, value) in data { parameters["context.data.\(key)"] = value }
        }

        return parameters
    }

}

public struct WidePixelErrorData: Codable {

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
