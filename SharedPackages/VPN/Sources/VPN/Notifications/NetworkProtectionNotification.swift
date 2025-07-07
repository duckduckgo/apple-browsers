//
//  NetworkProtectionNotification.swift
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

import Foundation
import Common
import os.log

#if os(macOS)

fileprivate extension Bundle {
    private static let networkProtectionDistributedNotificationPrefixKey = "DISTRIBUTED_NOTIFICATIONS_PREFIX"

    var networkProtectionDistributedNotificationPrefix: String {
        guard let bundleID = object(forInfoDictionaryKey: Self.networkProtectionDistributedNotificationPrefixKey) as? String else {
            fatalError("Info.plist is missing \(Self.networkProtectionDistributedNotificationPrefixKey)")
        }

        return bundleID
    }
}

extension DistributedNotificationCenter {
    // MARK: - Logging

    private func logPost(_ notification: NetworkProtectionNotification,
                         object: String? = nil) {

        if let string = object {
            Logger.networkProtectionMemory.debug("\(String(describing: Thread.current), privacy: .public): Distributed notification posted: \(notification.name.rawValue, privacy: .public) (\(string, privacy: .public))")
        } else {
            Logger.networkProtectionMemory.debug("Distributed notification posted: \(notification.name.rawValue, privacy: .public)")
        }
    }
}

extension DistributedNotificationCenter: NetworkProtectionNotificationPosting {
    public func post(_ networkProtectionNotification: NetworkProtectionNotification,
                     object: String? = nil,
                     userInfo: [AnyHashable: Any]? = nil) {
        logPost(networkProtectionNotification, object: object)

        postNotificationName(networkProtectionNotification.name, object: object, options: [.deliverImmediately, .postToAllSessions])
    }
}

public protocol NetworkProtectionNotificationPosting: AnyObject {
    func post(_ networkProtectionNotification: NetworkProtectionNotification, object: String?, userInfo: [AnyHashable: Any]?)
}

public extension NetworkProtectionNotificationPosting {
    func post(_ networkProtectionNotification: NetworkProtectionNotification, object: String? = nil, userInfo: [AnyHashable: Any]? = nil) {
        post(networkProtectionNotification, object: object, userInfo: userInfo)
    }
}

public typealias NetworkProtectionNotificationCenter = NotificationCenter & NetworkProtectionNotificationPosting

extension NotificationCenter {
    static let preferredStringEncoding = String.Encoding.utf8

    public func addObserver(for networkProtectionNotification: NetworkProtectionNotification,
                            object: Any?,
                            queue: OperationQueue?,
                            using block: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        addObserver(forName: networkProtectionNotification.name, object: object, queue: queue, using: block)
    }

    public func publisher(for networkProtectionNotification: NetworkProtectionNotification,
                          object: AnyObject? = nil) -> NotificationCenter.Publisher {
        self.publisher(for: networkProtectionNotification.name)
    }
}

public enum NetworkProtectionNotification: String {
    public enum UserInfoKey {
        public static let connectedServerLocation = "NetworkProtectionServerLocationKey"
    }

    // Tunnel Status
    case statusDidChange

    // Connection issues
    case issuesStarted
    case issuesResolved

    // User Notification Events
    case showIssuesStartedNotification
    case showConnectedNotification
    case showIssuesNotResolvedNotification
    case showVPNSupersededNotification
    case showExpiredEntitlementNotification
    case showTestNotification

    // Server Selection
    case serverSelected

    // Error Events
    case tunnelErrorChanged
    case controllerErrorChanged
    case knownFailureUpdated

    // New Status Observer
    case requestStatusUpdate

    fileprivate var name: Foundation.Notification.Name {
        NSNotification.Name(rawValue: fullNotificationName(for: rawValue))
    }

    private func fullNotificationName(for notificationName: String) -> String {
        "\(Bundle.main.networkProtectionDistributedNotificationPrefix).\(notificationName)"
    }
}

#endif
