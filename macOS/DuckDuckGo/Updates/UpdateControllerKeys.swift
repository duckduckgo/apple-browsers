//
//  UpdateControllerKeys.swift
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
import Persistence

/// Storage keys for AppUpdater package settings
public enum UpdateControllerStorageKeys: String, StorageKeyDescribing {
    // Update check state
    case pendingUpdateSince = "pending.update.since"
    case updateValidityStartDate = "update.validity.start.date"

    // Update preferences
    case automaticUpdates = "updates.automatic"
    case pendingUpdateShown = "pending.update.shown"

    // Debug settings
    case debugSparkleCustomFeedURL = "debug.sparkle.custom-feed-url"

    // Version tracking
    case previousAppVersion = "previous.app.version"
    case previousBuild = "previous.build"
    case lastSuccessfulUpdateDate = "updates.last.successful.date"

    // Pending update metadata (for validation)
    case pendingUpdateSourceVersion = "pending.update.source.version"
    case pendingUpdateSourceBuild = "pending.update.source.build"
    case pendingUpdateExpectedVersion = "pending.update.expected.version"
    case pendingUpdateExpectedBuild = "pending.update.expected.build"
    case pendingUpdateInitiationType = "pending.update.initiation.type"
    case pendingUpdateConfiguration = "pending.update.configuration"

    // Cached pending update info (PendingUpdateInfo stored as Codable)
    case pendingUpdateInfo = "com.duckduckgo.updateController.pendingUpdateInfo"
}

/// StoringKeys conforming struct for typed access to UpdateController settings
public struct UpdateControllerSettings: StoringKeys {
    // Update check state
    public let pendingUpdateSince = StorageKey<Date>(UpdateControllerStorageKeys.pendingUpdateSince, assertionHandler: { _ in })
    public let updateValidityStartDate = StorageKey<Date>(UpdateControllerStorageKeys.updateValidityStartDate, assertionHandler: { _ in })

    // Update preferences
    public let automaticUpdates = StorageKey<Bool>(UpdateControllerStorageKeys.automaticUpdates, assertionHandler: { _ in })
    public let pendingUpdateShown = StorageKey<Bool>(UpdateControllerStorageKeys.pendingUpdateShown, assertionHandler: { _ in })

    // Debug settings
    public let debugSparkleCustomFeedURL = StorageKey<String>(UpdateControllerStorageKeys.debugSparkleCustomFeedURL, assertionHandler: { _ in })

    // Version tracking
    public let previousAppVersion = StorageKey<String>(UpdateControllerStorageKeys.previousAppVersion, assertionHandler: { _ in })
    public let previousBuild = StorageKey<String>(UpdateControllerStorageKeys.previousBuild, assertionHandler: { _ in })
    public let lastSuccessfulUpdateDate = StorageKey<Date>(UpdateControllerStorageKeys.lastSuccessfulUpdateDate, assertionHandler: { _ in })

    // Pending update metadata (for validation)
    public let pendingUpdateSourceVersion = StorageKey<String>(UpdateControllerStorageKeys.pendingUpdateSourceVersion, assertionHandler: { _ in })
    public let pendingUpdateSourceBuild = StorageKey<String>(UpdateControllerStorageKeys.pendingUpdateSourceBuild, assertionHandler: { _ in })
    public let pendingUpdateExpectedVersion = StorageKey<String>(UpdateControllerStorageKeys.pendingUpdateExpectedVersion, assertionHandler: { _ in })
    public let pendingUpdateExpectedBuild = StorageKey<String>(UpdateControllerStorageKeys.pendingUpdateExpectedBuild, assertionHandler: { _ in })
    public let pendingUpdateInitiationType = StorageKey<String>(UpdateControllerStorageKeys.pendingUpdateInitiationType, assertionHandler: { _ in })
    public let pendingUpdateConfiguration = StorageKey<String>(UpdateControllerStorageKeys.pendingUpdateConfiguration, assertionHandler: { _ in })

    // Cached pending update info (PendingUpdateInfo stored as Codable)
    public let pendingUpdateInfo = StorageKey<PendingUpdateInfo>(UpdateControllerStorageKeys.pendingUpdateInfo, assertionHandler: { _ in })

    public init() {}
}
