//
//  NetworkProtectionEntitlementMonitor.swift
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

public actor NetworkProtectionEntitlementMonitor {
    public enum Result {
        case validEntitlement
        case invalidEntitlement
        case error(Error)
    }

    private static let monitoringInterval: TimeInterval = .minutes(20)

    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    var isStarted: Bool {
        task?.isCancelled == false
    }

    // MARK: - Init & deinit

    public init() {
        Logger.networkProtectionMemory.debug("[+] \(String(describing: self), privacy: .public)")
    }

    deinit {
        task?.cancel()

        Logger.networkProtectionMemory.debug("[-] \(String(describing: self), privacy: .public)")
    }

    // MARK: - Start/Stop monitoring

    public func start(entitlementCheck: @escaping () async -> Swift.Result<Bool, Error>, callback: @escaping (Result) async -> Void) {
        Logger.networkProtectionEntitlement.log("⚫️ Starting entitlement monitor")

        task = Task.periodic(interval: Self.monitoringInterval) {
            let result = await entitlementCheck()
            switch result {
            case .success(let hasEntitlement):
                if hasEntitlement {
                    Logger.networkProtectionEntitlement.log("⚫️ Valid entitlement")
                    await callback(.validEntitlement)
                } else {
                    Logger.networkProtectionEntitlement.log("⚫️ Invalid entitlement")
                    await callback(.invalidEntitlement)
                }
            case .failure(let error):
                Logger.networkProtectionEntitlement.error("⚫️ Error retrieving entitlement: \(error.localizedDescription, privacy: .public)")
                await callback(.error(error))
            }
        }
    }

    public func stop() {
        Logger.networkProtectionEntitlement.log("⚫️ Stopping entitlement monitor")

        task?.cancel() // Just making extra sure in case it's detached
        task = nil
    }
}
