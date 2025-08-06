//
//  DeviceSyncCoordinator.swift
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
import DDGSync
import Combine
import Common
import SystemConfiguration
import SyncUI_macOS
import SwiftUI
import Navigation
import PixelKit
import os.log
import BrowserServicesKit

protocol DeviceSyncCoordinating: AnyObject {
    @MainActor
    func presentDialog()
    @MainActor
    func dismissDialog()
}

final class DeviceSyncCoordinator: DeviceSyncCoordinating {
    var cancellable: AnyCancellable?

    init(managementDialogModel: ManagementDialogModel) {
        self.managementDialogModel = managementDialogModel
        cancellable = managementDialogModel.$currentDialog.sink { [weak self] dialog in
            Task {
                dialog == nil ? await self?.dismissDialog() : await self?.presentDialog()
            }
        }
    }

    private let managementDialogModel: ManagementDialogModel
    private var syncWindowController: NSWindowController?

    func startDeviceSync(returning: (() -> Void)? = nil) {
        // Clean up any existing sync session
        cleanUp()
    }

    @MainActor
    func presentDialog() {
        guard !(syncWindowController?.window?.isVisible ?? false) else {
            return
        }

        guard [AppVersion.AppRunType.normal, .uiTests].contains(AppVersion.runType) else {
            return
        }

        let syncViewController = SyncManagementDialogViewController(managementDialogModel)
        syncWindowController = syncViewController.wrappedInWindowController()

        guard let syncWindow = syncWindowController?.window,
              let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController
        else {
            assertionFailure("Sync: Failed to present SyncManagementDialogViewController")
            return
        }
        parentWindowController.window?.beginSheet(syncWindow)
    }

    @MainActor
    func dismissDialog() {
        guard let window = syncWindowController?.window, let sheetParent = window.sheetParent else {
            return
        }
        sheetParent.endSheet(window)
        cleanUp()
    }

    private func cleanUp() {
        syncWindowController?.close()
        syncWindowController = nil
    }
}
