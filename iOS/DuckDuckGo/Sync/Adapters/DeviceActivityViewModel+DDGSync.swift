//
//  DeviceActivityViewModel+DDGSync.swift
//  DuckDuckGo
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

import DDGSync
import SyncUI_iOS
import os.log

extension DeviceActivityViewModel {
    /// Connects Device Activity to Sync without adding a DDGSync dependency to SyncUI-iOS
    static func make(syncService: DDGSyncing) -> DeviceActivityViewModel {
        DeviceActivityViewModel(
            // Resolve the account on demand so account changes invalidate pending loads and review timers.
            accountIdentifier: { syncService.account?.userId },
            makePageFetcher: {
                let reader = try syncService.makeAuditLogReader()
                return {
                    let page = try await reader.nextPage()
                    return DeviceActivityPage(entries: page.events.map { event in
                        let action: DeviceActivityEntry.Action
                        switch event.kind {
                        case .synced: action = .synced
                        case .removed: action = .removed
                        }
                        return DeviceActivityEntry(id: event.id,
                                                   action: action,
                                                   date: event.occurredAt,
                                                   deviceName: event.device.name,
                                                   deviceType: event.device.type,
                                                   credentialId: event.device.credentialId)
                    }, hasMore: page.hasMore)
                }
            },
            // Per-account review dates preserve which activity is highlighted across visits and app restarts.
            loadReviewState: { accountID in
                do {
                    return try syncService.auditLogReviewState(for: accountID).map {
                        DeviceActivityReviewState(reviewedThrough: $0.reviewedThrough, isInitialized: $0.isInitialized)
                    }
                } catch {
                    Logger.sync.error("Failed to load Device Activity review state: \(String(reflecting: error), privacy: .private)")
                    return nil
                }
            },
            saveReviewState: { accountID, reviewState in
                let value = SyncAuditLogReviewState(reviewedThrough: reviewState.reviewedThrough, isInitialized: reviewState.isInitialized)
                do {
                    try syncService.setAuditLogReviewState(value, for: accountID)
                } catch {
                    Logger.sync.error("Failed to save Device Activity review state: \(String(reflecting: error), privacy: .private)")
                }
            }
        )
    }
}
