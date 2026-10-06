//
//  LoginItem.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import AppKit
import Foundation
import ServiceManagement
import os.log

public enum SMLoginItemSetEnabledError: Error {
    case failed
}

/// Takes care of enabling and disabling a login item.
///
public struct LoginItem: Equatable, Hashable {
    public let agentBundleID: String
    private let launchInformation: LoginItemLaunchInformation
    private let defaults: UserDefaults
    private let logger: Logger

    public var isRunning: Bool {
        !runningApplications.isEmpty
    }

    private var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID)
    }

    public var application: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).first
    }

    public enum Status {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound

        public var isEnabled: Bool {
            self == .enabled
        }

        public var isInstalled: Bool {
            self == .enabled || self == .requiresApproval
        }

        @available(macOS 13.0, *)
        public init(_ status: SMAppService.Status) {
            switch status {
            case .notRegistered: self = .notRegistered
            case .enabled: self = .enabled
            case .requiresApproval: self = .requiresApproval
            case .notFound: self = .notFound
            @unknown default: self = .notFound
            }
        }
    }

    /// Reads the login item status.
    ///
    /// The underlying `SMAppService` read performs synchronous XPC to the Service Management
    /// daemon, so it is dispatched onto a detached `Task` to keep it off the caller's thread
    /// (notably the main thread during launch).
    public func status() async -> Status {
        let agentBundleID = agentBundleID
        let logger = logger
        guard #available(macOS 13.0, *) else {
            return await Task.detached {
                guard let job = ServiceManagement.copyAllJobDictionaries(kSMDomainUserLaunchd).first(where: {
                    $0["Label"] as? String == agentBundleID
                }) else { return .notRegistered }

                logger.debug("🟢 found login item job: \(job.debugDescription, privacy: .public)")
                return job["OnDemand"] as? Bool == true ? .enabled : .requiresApproval
            }.value
        }
        return await Task.detached {
            Status(SMAppService.loginItem(identifier: agentBundleID).status)
        }.value
    }

    public init(bundleId: String, defaults: UserDefaults, logger: Logger) {
        self.agentBundleID = bundleId
        self.defaults = defaults
        self.launchInformation = LoginItemLaunchInformation(agentBundleID: bundleId, defaults: defaults)
        self.logger = logger
    }

    public func enable() async throws {
        logger.debug("🟢 registering login item \(self.debugDescription, privacy: .public)")

        let agentBundleID = agentBundleID
        if #available(macOS 13.0, *) {
            try await Task.detached {
                try SMAppService.loginItem(identifier: agentBundleID).register()
            }.value
        } else {
            try await Task.detached {
                if !SMLoginItemSetEnabled(agentBundleID as CFString, true) {
                    throw SMLoginItemSetEnabledError.failed
                }
            }.value
        }

        launchInformation.updateLastEnabledTimestamp()
    }

    public func disable() async throws {
        logger.debug("🟢 unregistering login item \(self.debugDescription, privacy: .public)")

        let agentBundleID = agentBundleID
        if #available(macOS 13.0, *) {
            try await Task.detached {
                try SMAppService.loginItem(identifier: agentBundleID).unregister()
            }.value
        } else {
            try await Task.detached {
                if !SMLoginItemSetEnabled(agentBundleID as CFString, false) {
                    throw SMLoginItemSetEnabledError.failed
                }
            }.value
        }
    }

    /// Restarts a login item.
    ///
    /// This call will only enable the login item if it was enabled to begin with.
    ///
    public func restart() async throws {
        guard await status() == .enabled else {
            logger.debug("🟢 restart not needed for login item \(self.debugDescription, privacy: .public)")
            return
        }
        try? await disable()
        try await enable()
    }

    public func forceStop() {
        let runningApplications = runningApplications
        logger.debug("🟢 stopping \(runningApplications.map { $0.processIdentifier }.description, privacy: .public)")
        runningApplications.forEach { $0.terminate() }
    }

    public static func == (lhs: LoginItem, rhs: LoginItem) -> Bool {
        lhs.agentBundleID == rhs.agentBundleID && lhs.launchInformation == rhs.launchInformation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(agentBundleID)
        hasher.combine(launchInformation)
    }
}

extension LoginItem: CustomDebugStringConvertible {

    public var debugDescription: String {
        "<LoginItem \(agentBundleID) isRunning: \(isRunning)>"
    }

}

private protocol ServiceManagementProtocol {
    func copyAllJobDictionaries(_ domain: CFString!) -> [[String: Any]]
    var errorDomain: String { get }
}
private struct SM: ServiceManagementProtocol {

    // suppress SMCopyAllJobDictionaries deprecation warning
    @available(macOS, introduced: 10.6, deprecated: 10.10)
    func copyAllJobDictionaries(_ domain: CFString!) -> [[String: Any]] {
        SMCopyAllJobDictionaries(domain).takeRetainedValue() as? [[String: Any]] ?? []
    }

    @available(macOS, introduced: 10.6, deprecated: 10.10)
    var errorDomain: String {
        if #available(macOS 13.0, *) {
            return "SMAppServiceErrorDomain"
        } else {
            return kSMErrorDomainLaunchd as String
        }
    }

}

private var ServiceManagement: ServiceManagementProtocol { SM() } // swiftlint:disable:this identifier_name
