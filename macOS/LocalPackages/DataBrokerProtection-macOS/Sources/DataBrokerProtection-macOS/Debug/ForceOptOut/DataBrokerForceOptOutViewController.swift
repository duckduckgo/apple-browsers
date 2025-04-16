//
//  DataBrokerForceOptOutViewController.swift
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
import SwiftUI
import DataBrokerProtectionCore
import PixelKit

public final class DataBrokerForceOptOutViewController: NSViewController {

    public override func loadView() {
        let fakeBroker = DataBrokerDebugFlagFakeBroker()
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)

        guard let pixelKit = PixelKit.shared else {
            fatalError("PixelKit not set up")
        }
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)

        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler)
        guard let vault = try? vaultFactory.makeVault(reporter: reporter) else {
            fatalError("Failed to make secure storage vault")
        }

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker, pixelHandler: sharedPixelsHandler, vault: vault)
        let dataManager = DataBrokerProtectionDataManager(database: database)

        let viewModel = DataBrokerForceOptOutViewModel(dataManager: dataManager)
        let contentView = DataBrokerForceOptOutView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.autoresizingMask = [.width, .height]
        self.view = hostingController.view
    }

}
