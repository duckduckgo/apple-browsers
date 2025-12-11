//
//  Logger+NetworkProtection.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import os.log

public extension Logger {
    fileprivate static let subsystem = "Network protection"
    static let networkProtection = Logger(subsystem: Logger.subsystem, category: "")
    static let networkProtectionBandwidthAnalysis = Logger(subsystem: Logger.subsystem, category: "Bandwidth Analysis")
    static let networkProtectionServerStatusMonitor = Logger(subsystem: Logger.subsystem, category: "Server Status Monitor")
    static let networkProtectionLatencyMonitor = Logger(subsystem: Logger.subsystem, category: "Latency Monitor")
    static let networkProtectionTunnelFailureMonitor = Logger(subsystem: Logger.subsystem, category: "Tunnel Failure Monitor")
    static let networkProtectionServerFailureRecovery = Logger(subsystem: Logger.subsystem, category: "Server Failure Recovery")
    static let networkProtectionConnectionTester = Logger(subsystem: Logger.subsystem, category: "Connection Tester")
    static let networkProtectionDistributedNotifications = Logger(subsystem: Logger.subsystem, category: "Distributed Notifications")
    static let networkProtectionIPC = Logger(subsystem: Logger.subsystem, category: "IPC")
    static let networkProtectionKeyManagement = Logger(subsystem: Logger.subsystem, category: "Key Management")
    static let networkProtectionMemory = Logger(subsystem: Logger.subsystem, category: "Memory")
    static let networkProtectionPixel = Logger(subsystem: Logger.subsystem, category: "Pixel")
    static let networkProtectionStatusReporter = Logger(subsystem: Logger.subsystem, category: "Status Reporter")
    static let networkProtectionSleep = Logger(subsystem: Logger.subsystem, category: "Sleep and Wake")
    static let networkProtectionEntitlement = Logger(subsystem: Logger.subsystem, category: "Entitlement Monitor")
    static let networkProtectionWireGuard = Logger(subsystem: Logger.subsystem, category: "WireGuardAdapter")
}
