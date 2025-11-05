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

/// Protocol for launching device sync flows.
///
/// Provides functionality to initiate the device synchronization flow,
/// allowing users to connect and sync with other devices.
protocol SyncDeviceFlowLaunching {
    /// Starts the device sync flow to connect with another device
    /// - Parameter completion: Optional closure called when the flow completes
    @MainActor
    func startDeviceSyncFlow(source: SyncDeviceButtonTouchpoint, completion: (() -> Void)?)
}

/// Delegate protocol for device sync coordination events.
///
/// Provides callbacks for significant events in the device sync coordination lifecycle,
/// allowing observers to respond to completion of sync flows.
protocol DeviceSyncCoordinationDelegate: AnyObject {
    /// Called when the sync flow has ended
    @MainActor
    func didEndFlow()
}

/// Coordinates device synchronization flows and manages sync dialog presentation.
///
/// This class serves as the main coordinator for device sync operations, handling
/// the presentation of sync dialogs, managing the sync flow lifecycle, and
/// coordinating between different sync-related components.
final class DeviceSyncCoordinator {
    var cancellable: AnyCancellable?

    @MainActor
    init(managementDialogModel: ManagementDialogModel = .init(), syncService: DDGSyncing, syncPausedStateManager: any SyncPausedStateManaging) {
        self.managementDialogModel = managementDialogModel
        self.dialogController = SyncDialogController(syncService: syncService, managementDialogModel: managementDialogModel, syncPausedStateManager: syncPausedStateManager)
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
    func startDeviceSyncFlow(source: SyncDeviceButtonTouchpoint, completion: (() -> Void)?) {
        presentDialog(completion: completion)
        Task {
            await dialogController.syncWithAnotherDevicePressed(source: source)
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

    func syncWithAnotherDevicePressed(source: SyncDeviceButtonTouchpoint?) async {
        presentDialog()
        await dialogController.syncWithAnotherDevicePressed(source: nil)
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

extension DeviceSyncCoordinator {

    @MainActor
    convenience init?() {
        guard let syncService = NSApp.delegateTyped.syncService, let errorHandler = NSApp.delegateTyped.syncDataProviders?.syncErrorHandler else {
            assertionFailure("Sync: Core dependencies not available")
            return nil
        }
        self.init(syncService: syncService, syncPausedStateManager: errorHandler)
    }
}
