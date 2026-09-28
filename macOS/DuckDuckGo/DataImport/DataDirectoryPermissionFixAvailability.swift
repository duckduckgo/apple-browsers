//
//  DataDirectoryPermissionFixAvailability.swift
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
struct DataDirectoryPermissionFixAvailability {

    private let featureFlagger: FeatureFlagger
    private let debugSettings: any KeyedStoring<DataImportDebugSettings>
    private let isOSSupported: Bool

    init(featureFlagger: FeatureFlagger,
         debugSettings: any KeyedStoring<DataImportDebugSettings>,
         isOSSupported: Bool = DataDirectoryPermissionFixAvailability.isRunningSupportedOS) {
        self.featureFlagger = featureFlagger
        self.debugSettings = debugSettings
        self.isOSSupported = isOSSupported
    }

    /// Debug override: run the flow regardless of the OS version, the Feature Flag, and the directory's actual access state.
    var mustForcePermissionFix: Bool {
        debugSettings.isForcingMacOS27PermissionsFix
    }

    /// Returns `true` running `macOS >= 27` and the `dataImportDataDirectoryAccess` Feature Flag is enabled.
    /// Can also be overridden via `isForcingMacOS27PermissionsFix`
    var isAvailable: Bool {
        if mustForcePermissionFix {
            return true
        }

        guard isOSSupported else {
            return false
        }

        return featureFlagger.isFeatureOn(.dataImportDataDirectoryAccess)
    }
}

extension DataDirectoryPermissionFixAvailability {

    /// `true` when the running OS is macOS +27.
    static var isRunningSupportedOS: Bool {
        if #available(macOS 27.0, *) {
            return true
        }
        return false
    }
}
