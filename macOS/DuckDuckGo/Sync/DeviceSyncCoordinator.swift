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

protocol SyncDeviceFlowLaunching {
    @MainActor
    func startDeviceSyncFlow(completion: (() -> Void)?)
}

protocol DeviceSyncCoordinationDelegate: AnyObject {
    @MainActor
    func didEndFlow()
}

final class DeviceSyncCoordinator {
    var cancellable: AnyCancellable?

    @MainActor
    init?(managementDialogModel: ManagementDialogModel = .init(), dialogController: SyncDialogController? = nil) {
        self.managementDialogModel = managementDialogModel
        guard let dialogController = dialogController ?? Self.createDialogController(managementDialogModel: managementDialogModel) else {
            return nil
        }
        self.dialogController = dialogController
        dialogController.coordinationDelegate = self
    }

    private let managementDialogModel: ManagementDialogModel
    private let dialogController: SyncDialogController
    private var syncWindowController: NSWindowController?

    @MainActor
    private func presentDialog(completion: (() -> Void)? = nil) {
        guard syncWindowController?.window?.isVisible != true else {
            return
        }

        guard [AppVersion.AppRunType.normal, .uiTests].contains(AppVersion.runType) else {
            return
        }

        let syncViewController = SyncManagementDialogViewController(managementDialogModel, dialogController: dialogController, coordinator: self)
        syncWindowController = syncViewController.wrappedInWindowController()

        guard let syncWindow = syncWindowController?.window,
              let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController
        else {
            assertionFailure("Sync: Failed to present SyncManagementDialogViewController")
            return
        }
        parentWindowController.window?.beginSheet(syncWindow) { _ in
            completion?()
        }
    }

    @MainActor
    private static func createDialogController(managementDialogModel: ManagementDialogModel) -> SyncDialogController? {
        guard let syncService = NSApp.delegateTyped.syncService, let errorHandler = NSApp.delegateTyped.syncDataProviders?.syncErrorHandler else {
            assertionFailure("Sync: Core dependencies not available")
            return nil
        }

        return SyncDialogController(syncService: syncService, managementDialogModel: managementDialogModel, syncPausedStateManager: errorHandler)
    }
}

extension DeviceSyncCoordinator: DeviceSyncCoordinationDelegate {
    @MainActor
    func didEndFlow() {
        guard let window = syncWindowController?.window, let sheetParent = window.sheetParent else {
            return
        }
        sheetParent.endSheet(window)
        syncWindowController?.close()

        // Very important to prevent a memory leak as there is a strong dependency
        // cycle between these types.
        syncWindowController = nil
    }
}

extension DeviceSyncCoordinator: SyncDeviceFlowLaunching {
    func startDeviceSyncFlow(completion: (() -> Void)?) {
        presentDialog(completion: completion)
        Task {
            await dialogController.syncWithAnotherDevicePressed()
        }
    }
}

extension DeviceSyncCoordinator: SyncSettingsViewHandling {
    func saveRecoveryPDF() {
        dialogController.saveRecoveryPDF()
    }

    var devicesPublisher: AnyPublisher<[SyncDevice], Never> {
        dialogController.devicesPublisher
    }

    func refreshDevices() {
        dialogController.refreshDevices()
    }

    func turnOffSyncPressed() {
        presentDialog()
        dialogController.turnOffSyncPressed()
    }

    func presentDeviceDetails(_ device: SyncUI_macOS.SyncDevice) {
        presentDialog()
        dialogController.presentDeviceDetails(device)
    }

    func presentRemoveDevice(_ device: SyncUI_macOS.SyncDevice) {
        presentDialog()
        dialogController.presentRemoveDevice(device)
    }

    func presentDeleteAccount() {
        presentDialog()
        dialogController.presentDeleteAccount()
    }

    func syncWithAnotherDevicePressed() async {
        presentDialog()
        await dialogController.syncWithAnotherDevicePressed()
    }

    func syncWithServerPressed() async {
        presentDialog()
        await dialogController.syncWithServerPressed()
    }

    func recoverDataPressed() async {
        presentDialog()
        await dialogController.recoverDataPressed()
    }
}
