//
//  DataImportEntryPointHandler.swift
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

import PrivacyConfig

struct DataImportEntryPointHandler {

    enum Destination: Equatable {
        case legacy(importScreen: DataImportViewModel.ImportScreen)
        case hub
    }

    private let featureFlagger: FeatureFlagger
    private let isSupportedOSVersion: () -> Bool

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         isSupportedOSVersion: @escaping () -> Bool = {
             if #available(iOS 26.4, *) {
                 return true
             } else {
                 return false
             }
         }) {
        self.featureFlagger = featureFlagger
        self.isSupportedOSVersion = isSupportedOSVersion
    }

    func destination(for importScreen: DataImportViewModel.ImportScreen) -> Destination {
        if shouldRouteToNewUI {
            return .hub
        }
        return .legacy(importScreen: importScreen)
    }

    private var shouldRouteToNewUI: Bool {
        isSupportedOSVersion() && featureFlagger.isFeatureOn(.dataImportNewUI)
    }
}
