//
//  Logger+DataBrokerProtection.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
    static let dbpSubsystem = "PIR"

    static var dataBrokerProtection = {
        Logger(subsystem: dbpSubsystem, category: DataBrokerProtectionLoggerCategory.dataBrokerProtection.rawValue)
    }()
    static var action = {
        Logger(subsystem: dbpSubsystem, category: DataBrokerProtectionLoggerCategory.action.rawValue)
    }()
    static var service = {
        Logger(subsystem: dbpSubsystem, category: DataBrokerProtectionLoggerCategory.service.rawValue)
    }()
    static var backgroundAgent = {
        Logger(subsystem: dbpSubsystem, category: DataBrokerProtectionLoggerCategory.backgroundAgent.rawValue)
    }()
    static var backgroundAgentMemoryManagement = {
        Logger(subsystem: dbpSubsystem, category: DataBrokerProtectionLoggerCategory.backgroundAgentMemoryManagement.rawValue)
    }()
    static var pixel = {
        Logger(subsystem: dbpSubsystem, category: DataBrokerProtectionLoggerCategory.pixel.rawValue)
    }()
}

public enum DataBrokerProtectionLoggerCategory: String, CaseIterable, Identifiable {
    case dataBrokerProtection = "Data Broker Protection"
    case action = "Action"
    case service = "Service"
    case backgroundAgent = "Background Agent"
    case backgroundAgentMemoryManagement = "Background Agent Memory Management"
    case pixel = "Pixel"

    public var id: String { rawValue }
}
