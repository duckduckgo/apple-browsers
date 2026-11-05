//
//  SyncAuditLog.swift
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

public struct SyncAuditLogEvent: Sendable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case synced
        case removed
    }

    public let id: String
    public let kind: Kind
    public let occurredAt: Date
    public let device: RegisteredDevice

    public init(id: String, kind: Kind, occurredAt: Date, device: RegisteredDevice) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.device = device
    }
}

public struct SyncAuditLogPage: Sendable {
    public let events: [SyncAuditLogEvent]
    public let hasMore: Bool

    public init(events: [SyncAuditLogEvent], hasMore: Bool) {
        self.events = events
        self.hasMore = hasMore
    }
}

@MainActor
public protocol SyncAuditLogReading: AnyObject {
    func nextPage() async throws -> SyncAuditLogPage
}

/// Reads one account's history for one screen visit. API order defines login boundaries, including same-second events.
@MainActor
final class SyncAuditLogReader: SyncAuditLogReading {
    private enum DeviceInfoCandidate {
        case readable(name: String, type: String)
        case unreadable
    }

    private let account: SyncAccount
    private let fetchPage: (SyncAccount, String?) async throws -> AuditLogPage
    private var beforeCursor: String?
    private var hasMore = true
    private var visitedCursors = Set<String>()
    private var processedEventIDs = Set<String>()
    private var pendingDeviceInfo = [String: DeviceInfoCandidate]()

    init(account: SyncAccount, fetchPage: @escaping (SyncAccount, String?) async throws -> AuditLogPage) {
        self.account = account
        self.fetchPage = fetchPage
    }

    func nextPage() async throws -> SyncAuditLogPage {
        guard hasMore else { return SyncAuditLogPage(events: [], hasMore: false) }
        try Task.checkCancellation()
        let page = try await fetchPage(account, beforeCursor)
        try Task.checkCancellation()
        var events = [SyncAuditLogEvent]()
        for result in page.entries {
            guard case .decoded(let event) = result, processedEventIDs.insert(event.id).inserted else { continue }
            switch event.type {
            case .deviceInfoAdded:
                // Later candidates in the newest-first stream are older. An unreadable one also replaces its predecessor.
                pendingDeviceInfo[event.device.id] = event.hasDeviceInfo
                    ? .readable(name: event.device.name, type: event.device.type) : .unreadable
            case .login:
                let candidate = pendingDeviceInfo.removeValue(forKey: event.device.id)
                var device = event.device
                if !event.hasDeviceInfo, case .readable(let name, let type)? = candidate {
                    device = RegisteredDevice(id: device.id, name: name, type: type, credentialId: device.credentialId)
                }
                events.append(SyncAuditLogEvent(id: event.id, kind: .synced, occurredAt: event.occurredAt, device: device))
            case .logout:
                events.append(SyncAuditLogEvent(id: event.id, kind: .removed, occurredAt: event.occurredAt, device: event.device))
            }
        }
        if let nextCursor = page.before, nextCursor != beforeCursor, visitedCursors.insert(nextCursor).inserted {
            beforeCursor = nextCursor
        } else {
            hasMore = false
            pendingDeviceInfo.removeAll()
        }
        return SyncAuditLogPage(events: events, hasMore: hasMore)
    }
}

public struct SyncAuditLogReviewState: Codable, Sendable, Equatable {
    public let reviewedThrough: Date?
    public let isInitialized: Bool

    public init(reviewedThrough: Date?, isInitialized: Bool) {
        self.reviewedThrough = reviewedThrough
        self.isInitialized = isInitialized
    }
}
