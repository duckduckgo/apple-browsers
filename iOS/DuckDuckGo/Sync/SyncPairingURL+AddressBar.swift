//
//  SyncPairingURL+AddressBar.swift
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

import Common
import DDGSync
import FeatureFlags_iOS
import Foundation
import PrivacyConfig

extension SyncPairingURL {

    init?(addressBarQuery: String, syncService: DDGSyncing, featureFlagger: FeatureFlagger, useUnifiedLogic: Bool) {
        guard featureFlagger.isFeatureOn(.syncPairingUrl),
              syncService.featureFlags.contains(.connectFlows),
              syncService.authState != .inactive || syncService.featureFlags.contains(.accountCreation),
              let url = URL(trimmedAddressBarString: addressBarQuery.trimmingCharacters(in: .whitespacesAndNewlines), useUnifiedLogic: useUnifiedLogic) else {
            return nil
        }
        self.init(url: url)
    }
}
