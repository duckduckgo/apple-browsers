//
//  VPNIPLeakCheckWideEventData.swift
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
import PixelKit

public final class VPNIPLeakCheckWideEventData: WideEventData {

    public static let metadata = WideEventMetadata(
        pixelName: "vpn_ip_leak_check",
        featureName: "vpn-ip-leak-check",
        mobileMetaType: "ios-vpn-ip-leak-check",
        desktopMetaType: "macos-vpn-ip-leak-check",
        version: "1.1.0"
    )

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData
    public var errorData: WideEventErrorData?

    public var trigger: LeakCheckTrigger
    public var latencyMsBucketed: Int?
    public var statusReason: String?
    public var egressServerName: String?

    public var ipv4Http: LeakCheckPerTestResult?
    public var ipv4Https: LeakCheckPerTestResult?
    public var ipv4Stun: LeakCheckPerTestResult?
    public var ipv4LeakIPType: LeakIPType?

    public var ipv6Http: LeakCheckPerTestResult?
    public var ipv6Https: LeakCheckPerTestResult?
    public var ipv6Stun: LeakCheckPerTestResult?
    public var ipv6LeakIPType: LeakIPType?

    public init(
        trigger: LeakCheckTrigger,
        appData: WideEventAppData = WideEventAppData(),
        globalData: WideEventGlobalData = WideEventGlobalData()
    ) {
        self.trigger = trigger
        self.contextData = WideEventContextData()
        self.appData = appData
        self.globalData = globalData
    }

    public func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        switch trigger {
        case .appLaunch:
            return .complete(.unknown(reason: "check_interrupted"))
        }
    }

    public func jsonParameters() -> [String: Encodable] {
        var params: [String: Encodable] = ["feature.data.ext.trigger": trigger.rawValue]

        if let latency = latencyMsBucketed { params["feature.data.ext.latency_ms_bucketed"] = latency }
        if let reason = statusReason { params["feature.data.ext.status_reason"] = reason }
        if let serverName = egressServerName { params["feature.data.ext.egress_server_name"] = serverName }
        if let leakType = ipv4LeakIPType { params["feature.data.ext.ipv4.leak_ip_type"] = leakType.rawValue }
        if let leakType = ipv6LeakIPType { params["feature.data.ext.ipv6.leak_ip_type"] = leakType.rawValue }

        add(result: ipv4Http, version: .v4, test: .http, to: &params)
        add(result: ipv4Https, version: .v4, test: .https, to: &params)
        add(result: ipv4Stun, version: .v4, test: .stun, to: &params)
        add(result: ipv6Http, version: .v6, test: .http, to: &params)
        add(result: ipv6Https, version: .v6, test: .https, to: &params)
        add(result: ipv6Stun, version: .v6, test: .stun, to: &params)

        return params
    }

    private func add(
        result: LeakCheckPerTestResult?,
        version: IPVersion,
        test: LeakCheckProtocol,
        to params: inout [String: Encodable]
    ) {
        guard let result = result else {
            return
        }

        let prefix = "feature.data.ext.\(version.rawValue).\(test.rawValue)"
        params["\(prefix).status"] = result.status.rawValue

        if let domain = result.errorDomain { params["\(prefix).error_domain"] = domain }
        if let code = result.errorCode { params["\(prefix).error_code"] = code }
        if let domain = result.underlyingDomain { params["\(prefix).underlying_domain"] = domain }
        if let code = result.underlyingCode { params["\(prefix).underlying_code"] = code }
        if let matched = result.octet1Matched { params["\(prefix).leak_octet1_matched"] = matched }
        if let matched = result.octet2Matched { params["\(prefix).leak_octet2_matched"] = matched }
        if let matched = result.octet3Matched { params["\(prefix).leak_octet3_matched"] = matched }
        if let matched = result.octet4Matched { params["\(prefix).leak_octet4_matched"] = matched }
    }
}
