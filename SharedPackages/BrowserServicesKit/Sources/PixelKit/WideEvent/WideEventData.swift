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
    /// The name used when sending the pixel.
    /// This will be appended to `m_(ios|macos)_wide_`.
    static var pixelName: String { get }

    /// The name used in the event payload. This is used to identify the feature that the event is related to, and can be the same across platforms.
    static var featureName: String { get }

    /// Data about the context that the event was sent in, such as the parent feature that the event is operating in.
    /// For example, the context name for a data import event could be the flow that triggered the import, such as onboarding.
    var contextData: WideEventContextData { get set }

    /// Data sent with all wide events, such as sample rate and event type.
    var globalData: WideEventGlobalData { get set }

    /// Data about the current install of the app, such as version and form factor.
    var appData: WideEventAppData { get set }

    /// Optional error data.
    /// All layers of underlying errors will be reported.
    var errorData: WideEventErrorData? { get set }

    /// Returns the completion decision for this event based on the given trigger.
    /// Override this method to provide custom completion logic for your event type.
    func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision
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
    public static let minimumSampleRate: Float = 0.0
    public static let maximumSampleRate: Float = 1.0

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

    public init(id: String = UUID().uuidString, platform: String = DevicePlatform.currentPlatform.rawValue, sampleRate: Float = Self.maximumSampleRate) {
        if sampleRate > Self.maximumSampleRate || sampleRate < Self.minimumSampleRate {
            assertionFailure("Sample rate must be between 0-1")
        }

        self.id = id
        self.platform = platform
        self.type = "app" // Don't allow type to be overridden
        self.sampleRate = sampleRate.clamped(to: Self.minimumSampleRate...Self.maximumSampleRate)
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

    public func jsonParameters() -> [String: Encodable] {
        var parameters: [String: Encodable] = [:]

        parameters[WideEventParameter.Global.platform] = platform
        parameters[WideEventParameter.Global.type] = type
        parameters[WideEventParameter.Global.sampleRate] = sampleRate

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

    public init(name: String = Self.defaultAppName(),
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

    /// Returns the appropriate app name for the current platform.
    /// - macOS: Uses CFBundleName (the bundle name)
    /// - iOS: Uses CFBundleExecutable (the product name, which maps to Xcode targets)
    public static func defaultAppName() -> String {
        #if os(iOS)
        let productName = AppVersion.shared.productName

        // We can't check whether we're running in the alpha build from BSK, but need to avoid sending the alpha
        // product name - this check intercepts the alpha product name and returns the default app name instead.
        if productName == "DuckDuckGo-Alpha" {
            return "DuckDuckGo"
        } else {
            return productName
        }
        #else
        return AppVersion.shared.name
        #endif
    }
}

extension WideEventAppData: WideEventParameterProviding {

    public func pixelParameters() -> [String: String] {
        Dictionary(compacting: [
            (WideEventParameter.App.name, name),
            (WideEventParameter.App.version, version),
            (WideEventParameter.App.formFactor, formFactor),
            (WideEventParameter.App.internalUser, internalUser == true ? "true" : nil),
        ])
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
        Dictionary(compacting: [
            (WideEventParameter.Context.name, name),
        ])
    }

}

// MARK: - WideEventErrorData

public struct WideEventErrorData: Codable {

    public var domain: String
    public var code: Int
    public var description: String?
    public var underlyingErrors: [UnderlyingError]

    public init(error: Error, description: String? = nil) {
        let nsError = error as NSError
        self.domain = nsError.domain
        self.code = nsError.code
        self.description = description

        self.underlyingErrors = Self.collectUnderlyingErrors(from: nsError)
    }

}

extension WideEventErrorData {
    public struct UnderlyingError: Codable {
        public let domain: String
        public let code: Int
    }

    private static func collectUnderlyingErrors(from error: NSError?) -> [UnderlyingError] {
        guard let error else { return [] }

        var collected: [UnderlyingError] = []
        var current = error.userInfo[NSUnderlyingErrorKey] as? NSError

        while let nsError = current {
            collected.append(UnderlyingError(domain: nsError.domain, code: nsError.code))
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return collected
    }
}

extension WideEventErrorData: WideEventParameterProviding {
    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WideEventParameter.Feature.errorDomain] = domain
        parameters[WideEventParameter.Feature.errorCode] = String(code)
        parameters[WideEventParameter.Feature.errorDescription] = description

        for (index, nested) in underlyingErrors.enumerated() {
            let suffix = index == 0 ? "" : String(index + 1)
            parameters[WideEventParameter.Feature.underlyingErrorDomain + suffix] = nested.domain
            parameters[WideEventParameter.Feature.underlyingErrorCode + suffix] = String(nested.code)
        }

        return parameters
    }
}

extension WideEvent.MeasuredInterval {

    public var durationMilliseconds: Double? {
        guard let start, let end else { return nil }
        return max(end.timeIntervalSince(start) * 1000, 0)
    }

    public func stringValue(_ bucket: DurationBucket) -> String? {
        durationMilliseconds.map { String(bucket.apply($0)) }
    }

}

public enum DurationBucket {
    case noBucketing
    case bucketed((Double) -> Int)

    func apply(_ ms: Double) -> Int {
        switch self {
        case .noBucketing:
            return Int(ms)
        case .bucketed(let fn):
            return fn(ms)
        }
    }
}
