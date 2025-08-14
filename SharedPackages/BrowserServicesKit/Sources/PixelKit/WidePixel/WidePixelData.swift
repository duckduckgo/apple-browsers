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

public protocol WidePixelParameterProviding {
    func pixelParameters() -> [String: String]
}

public protocol WidePixelData: Codable, WidePixelParameterProviding {
    static var pixelName: String { get }
    var contextData: WidePixelContextData { get set }
    var appData: WidePixelAppData { get set }
    var globalData: WidePixelGlobalData { get set }
}

public extension WidePixelParameterProviding {
    func pixelParameters() -> [String: String] { [:] }
}

public enum WidePixelFinalStatus: Codable {
    case success
    case failure
    case cancelled
    case unknown(reason: String)

    public var asString: String {
        switch self {
        case .success: return "SUCCESS"
        case .failure: return "FAILURE"
        case .cancelled: return "CANCELLED"
        case .unknown: return "UNKNOWN"
        }
    }

    private enum CodingKeys: String, CodingKey { case type, reason }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(asString, forKey: .type)
        if case let .unknown(reason) = self { try container.encode(reason, forKey: .reason) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "SUCCESS": self = .success
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

public struct MeasuredInterval: Codable {
    public var start: Date?
    public var end: Date?

    public init(start: Date? = nil, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

public struct WidePixelGlobalData: Codable {
    public var platform: String
    public let type: String
    public var sampleRate: Double

    public init() {
        self.init(platform: PlatformInfo.displayName, sampleRate: 1.0)
    }

    public init(platform: String, sampleRate: Double) {
        if sampleRate > 1.0 || sampleRate < 0.0 {
            assertionFailure("Sample rate must be between 0-1")
        }

        self.platform = platform
        self.type = "app" // Don't allow type to be overridden
        self.sampleRate = sampleRate
    }
}

public struct WidePixelAppData: Codable {
    public var name: String
    public var version: String
    public var formFactor: String?
}

public extension WidePixelAppData {
    init() {
        self.name = PlatformInfo.appName
        self.version = PlatformInfo.appVersion
        self.formFactor = PlatformInfo.formFactor
    }
}

extension WidePixelGlobalData: WidePixelParameterProviding {
    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]
        parameters["global.platform"] = platform
        parameters["global.type"] = type
        parameters["global.sample_rate"] = String(sampleRate)
        return parameters
    }
}

extension WidePixelAppData: WidePixelParameterProviding {
    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]
        parameters["app.name"] = name
        parameters["app.version"] = version
        if let formFactor = formFactor {
            parameters["global.form_factor"] = formFactor
        }
        return parameters
    }
}

public struct WidePixelContextData: Codable {
    public let id: UUID
    public var name: String?
    public var data: [String: String]?

    public init(id: UUID = UUID(), name: String? = nil, data: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.data = data
    }
}

extension WidePixelContextData: WidePixelParameterProviding {
    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]
        if let name = name { parameters["context.name"] = name }
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
