//
//  LeakCheckModels.swift
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

public enum LeakCheckTrigger: String, Codable {
    case tunnelStart = "tunnel_start"
    case reassert
    case periodic
}

public struct LeakCheckEgressInfo: Equatable, Sendable {
    public let ipAddress: String
    public let name: String

    public init(ipAddress: String, name: String) {
        self.ipAddress = ipAddress
        self.name = name
    }
}

public enum IPVersion: String {
    case v4 = "ipv4"
    case v6 = "ipv6"
}

public enum LeakCheckProtocol: String {
    case http
    case https
    case stun
}

public struct LeakCheckPerTestResult: Codable, Equatable {

    public enum Status: String, Codable {
        case success
        case leak
        case error
    }

    public let status: Status
    public let errorDomain: String?
    public let errorCode: Int?
    public let underlyingDomain: String?
    public let underlyingCode: Int?

    public init(
        status: Status,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        underlyingDomain: String? = nil,
        underlyingCode: Int? = nil
    ) {
        self.status = status
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.underlyingDomain = underlyingDomain
        self.underlyingCode = underlyingCode
    }

    public static let success = LeakCheckPerTestResult(status: .success)
    public static let leak = LeakCheckPerTestResult(status: .leak)

    public static func error(_ error: Error) -> LeakCheckPerTestResult {
        let ns = error as NSError
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        return LeakCheckPerTestResult(
            status: .error,
            errorDomain: ns.domain,
            errorCode: ns.code,
            underlyingDomain: underlying?.domain,
            underlyingCode: underlying?.code
        )
    }
}

public struct LeakCheckConfiguration {
    public let host: String
    public let httpPort: UInt16
    public let httpsPort: UInt16
    public let stunPort: UInt16
    public let httpTimeout: TimeInterval
    public let stunTimeout: TimeInterval
    public let periodicInterval: TimeInterval
    public let cooldown: TimeInterval
    public let tunnelStartDelay: TimeInterval

    public static let `default` = LeakCheckConfiguration(
        host: "leakcheck.netp.duckduckgo.com",
        httpPort: 80,
        httpsPort: 443,
        stunPort: 3478,
        httpTimeout: 10,
        stunTimeout: 5,
        periodicInterval: 4 * 60 * 60,
        cooldown: 30,
        tunnelStartDelay: 5
    )

    public init(
        host: String,
        httpPort: UInt16,
        httpsPort: UInt16,
        stunPort: UInt16,
        httpTimeout: TimeInterval,
        stunTimeout: TimeInterval,
        periodicInterval: TimeInterval,
        cooldown: TimeInterval,
        tunnelStartDelay: TimeInterval
    ) {
        self.host = host
        self.httpPort = httpPort
        self.httpsPort = httpsPort
        self.stunPort = stunPort
        self.httpTimeout = httpTimeout
        self.stunTimeout = stunTimeout
        self.periodicInterval = periodicInterval
        self.cooldown = cooldown
        self.tunnelStartDelay = tunnelStartDelay
    }
}
