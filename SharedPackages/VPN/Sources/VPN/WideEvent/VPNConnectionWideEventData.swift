//
//  VPNConnectionWideEventData.swift
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
import PixelKit

public class VPNConnectionWideEventData: WideEventData {

    #if DEBUG
    public static let pixelName = "m_ios_wide_vpn_connection_debug"
    #else
    public static let pixelName = "m_ios_wide_vpn_connection"
    #endif

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    // VPN-specific
    public let extensionType: ExtensionType
    public let startupMethod: StartupMethod

    // Overall duration
    public var overallDuration: WideEvent.MeasuredInterval?

    // Per-step durations
    public var browserStartDuration: WideEvent.MeasuredInterval?
    public var controllerStartDuration: WideEvent.MeasuredInterval?
    public var oauthDuration: WideEvent.MeasuredInterval?
    public var tunnelStartDuration: WideEvent.MeasuredInterval?

    // Per-step errors
    public var browserStartError: WideEventErrorData?
    public var controllerStartError: WideEventErrorData?
    public var oauthError: WideEventErrorData?
    public var tunnelStartError: WideEventErrorData?

    public var errorData: WideEventErrorData?

    public init(extensionType: ExtensionType,
                startupMethod: StartupMethod,
                overallDuration: WideEvent.MeasuredInterval? = nil,
                browserStartDuration: WideEvent.MeasuredInterval? = nil,
                controllerStartDuration: WideEvent.MeasuredInterval? = nil,
                oauthDuration: WideEvent.MeasuredInterval? = nil,
                tunnelStartDuration: WideEvent.MeasuredInterval? = nil,
                browserStartError: WideEventErrorData? = nil,
                controllerStartError: WideEventErrorData? = nil,
                oauthError: WideEventErrorData? = nil,
                tunnelStartError: WideEventErrorData? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.extensionType = extensionType
        self.startupMethod = startupMethod
        self.overallDuration = overallDuration

        // Per-step latencies
        self.browserStartDuration = browserStartDuration
        self.controllerStartDuration = controllerStartDuration
        self.oauthDuration = oauthDuration
        self.tunnelStartDuration = tunnelStartDuration

        // Per-step errors
        self.browserStartError = browserStartError
        self.controllerStartError = controllerStartError
        self.oauthError = oauthError
        self.tunnelStartError = tunnelStartError

        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    private static let featureName = "vpn-connection"
}

// MARK: - Public

extension VPNConnectionWideEventData {

    public enum ExtensionType: String, Codable, CaseIterable {
        case app
        case system
    }

    public enum StartupMethod: String, Codable, CaseIterable {
        case automaticOnDemand = "automatic_on_demand"
        case manualByMainApp = "manual_by_main_app"
        case manualByTheSystem = "manual_by_the_system"
    }

    public enum StatusReason: String {
        case partialData = "partial_data"
        case timeout
    }

    public enum Step: String, Codable, CaseIterable {
        case browserStart = "browser_start"
        case controllerStart = "controller_start"
        case oauth = "oauth"
        case tunnelStart = "tunnel_start"

        public var durationPath: WritableKeyPath<VPNConnectionWideEventData, WideEvent.MeasuredInterval?> {
            switch self {
            case .browserStart: return \.browserStartDuration
            case .controllerStart: return \.controllerStartDuration
            case .oauth: return \.oauthDuration
            case .tunnelStart: return \.tunnelStartDuration
            }
        }

        public var errorPath: WritableKeyPath<VPNConnectionWideEventData, WideEventErrorData?> {
            switch self {
            case .browserStart: return \.browserStartError
            case .controllerStart: return \.controllerStartError
            case .oauth: return \.oauthError
            case .tunnelStart: return \.tunnelStartError
            }
        }
    }

    public func pixelParameters() -> [String: String] {
        var params: [String: String] = [:]

        params[WideEventParameter.Feature.name] = Self.featureName
        params[WideEventParameter.VPNConnectionFeature.extensionType] = extensionType.rawValue
        params[WideEventParameter.VPNConnectionFeature.startupMethod] = startupMethod.rawValue

        // Overall latency
        if let overallDuration = overallDuration?.durationMilliseconds {
            params[WideEventParameter.VPNConnectionFeature.latency] = String(Int(overallDuration))
        }

        for step in Step.allCases {
            addStepLatency(self[keyPath: step.durationPath], step: step, to: &params)
            addStepError(self[keyPath: step.errorPath], step: step, to: &params)
        }

        return params
    }
}

// MARK: - Private

private extension VPNConnectionWideEventData {

    func addStepLatency(_ interval: WideEvent.MeasuredInterval?, step: Step, to params: inout [String: String]) {
        guard let duration = interval?.durationMilliseconds else { return }
        params[WideEventParameter.VPNConnectionFeature.latency(at: step)] = String(Int(duration))
    }

    func addStepError(_ error: WideEventErrorData?, step: Step, to params: inout [String: String]) {
        guard let error else { return }
        let errorParams = error.pixelParameters()
        for (key, value) in errorParams {
            let stepKey = transformErrorKey(key, for: step)
            params[stepKey] = value
        }
    }

    func transformErrorKey(_ key: String, for step: Step) -> String {
        switch key {
        case WideEventParameter.Feature.errorDomain:
            return WideEventParameter.VPNConnectionFeature.errorDomain(at: step)

        case WideEventParameter.Feature.errorCode:
            return WideEventParameter.VPNConnectionFeature.errorCode(at: step)

        case WideEventParameter.Feature.errorDescription:
            return WideEventParameter.VPNConnectionFeature.errorDescription(at: step)

        case let key where key.hasPrefix(WideEventParameter.Feature.underlyingErrorDomain):
            let suffix = key.dropFirst(WideEventParameter.Feature.underlyingErrorDomain.count)
            return WideEventParameter.VPNConnectionFeature.errorUnderlyingDomain(at: step, suffix: String(suffix))

        case let key where key.hasPrefix(WideEventParameter.Feature.underlyingErrorCode):
            let suffix = key.dropFirst(WideEventParameter.Feature.underlyingErrorCode.count)
            return WideEventParameter.VPNConnectionFeature.errorUnderlyingCode(at: step, suffix: String(suffix))

        default:
            assertionFailure("Unexpected error parameter key: \(key)")
            return key
        }
    }
}

// MARK: - Wide Event Parameters
extension WideEventParameter {

    public enum VPNConnectionFeature {
        static let extensionType = "feature.data.ext.extension_type"
        static let startupMethod = "feature.data.ext.startup_method"
        static let latency = "feature.data.ext.latency_ms"

        static func latency(at step: VPNConnectionWideEventData.Step) -> String {
            "feature.data.ext.\(step.rawValue)_latency_ms"
        }

        static func errorDomain(at step: VPNConnectionWideEventData.Step) -> String {
            "feature.data.ext.\(step.rawValue)_error.domain"
        }

        static func errorCode(at step: VPNConnectionWideEventData.Step) -> String {
            "feature.data.ext.\(step.rawValue)_error.code"
        }

        static func errorDescription(at step: VPNConnectionWideEventData.Step) -> String {
            "feature.data.ext.\(step.rawValue)_error.description"
        }

        static func errorUnderlyingDomain(at step: VPNConnectionWideEventData.Step, suffix: String) -> String {
            return "feature.data.ext.\(step.rawValue)_error.underlying_domain\(suffix)"
        }

        static func errorUnderlyingCode(at step: VPNConnectionWideEventData.Step, suffix: String) -> String {
            return "feature.data.ext.\(step.rawValue)_error.underlying_code\(suffix)"
        }
    }
}
