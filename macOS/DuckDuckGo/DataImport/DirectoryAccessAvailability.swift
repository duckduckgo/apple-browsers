//
//  DirectoryAccessAvailability.swift
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

import FeatureFlags_macOS
import Foundation
import Persistence
import PrivacyConfig

/// Whether the data-directory access flow applies.
///
/// macOS 27+ denies apps with `com.apple.security.*` entitlements access to other apps'
/// `~/Library/Application Support/*` directories (TCC), so browser profiles can't be read until the user grants it.
struct DirectoryAccessAvailability {

    private static let minimumRequiredMacVersion = 27

    private let featureFlagger: FeatureFlagger
    private let debugSettings: any KeyedStoring<DataImportDebugSettings>
    private let operatingSystemVersion: OperatingSystemVersion

    init(featureFlagger: FeatureFlagger,
         debugSettings: any KeyedStoring<DataImportDebugSettings>,
         operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) {
        self.featureFlagger = featureFlagger
        self.debugSettings = debugSettings
        self.operatingSystemVersion = operatingSystemVersion
    }

    /// Debug override: run the flow regardless of the OS version, the Feature Flag, and the directory's actual access state.
    var mustForcePermissionFix: Bool {
        debugSettings.isForcingMacOS27PermissionsFix
    }

    /// Returns `true` running `macOS >= 27` and the `dataImportDataDirectoryAccess` Feature Flag is enabled.
    /// Can also be overridden via `isForcingMacOS27PermissionsFix`
    var isEnabled: Bool {
        if mustForcePermissionFix {
            return true
        }

        if operatingSystemVersion.majorVersion < Self.minimumRequiredMacVersion {
            return false
        }

        return featureFlagger.isFeatureOn(.dataImportDataDirectoryAccess)
    }
}
