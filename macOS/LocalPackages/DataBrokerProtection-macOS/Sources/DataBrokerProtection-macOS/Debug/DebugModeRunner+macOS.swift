//
//  DebugModeRunner+macOS.swift
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

import DataBrokerProtectionCore
import Foundation
import PixelKit

extension DebugModeRunner {

    convenience init(authenticationManager: DataBrokerProtectionAuthenticationManaging,
                     featureFlagger: DBPFeatureFlagging) throws {
        let privacyConfigManager = DBPPrivacyConfigurationManager()
        let pixelHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: PixelKit.shared!, platform: .macOS)
        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: pixelHandler, privacyConfigManager: privacyConfigManager)
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
        self.init(authenticationManager: authenticationManager,
                  featureFlagger: featureFlagger,
                  privacyConfigManager: privacyConfigManager,
                  pixelHandler: pixelHandler,
                  vault: try vaultFactory.makeVault(reporter: reporter),
                  settings: DataBrokerProtectionSettings(defaults: .dbp))
    }
}
