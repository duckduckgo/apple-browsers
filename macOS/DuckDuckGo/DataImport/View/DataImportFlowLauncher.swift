//
//  DataImportFlowLauncher.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AppKit
import DDGSync
import BrowserServicesKit
import FeatureFlags

/// Protocol for re-launching data import flows from within data import
///
/// Provides functionality to initiate data import flows with customizable
/// presentation options and data type selection.
protocol DataImportFlowRelaunching {
    /// Launches the data import flow with the specified configuration
    /// - Parameters:
    ///   - model: The view model containing import data and state
    @MainActor
    func relaunchDataImport(
        model: DataImportViewModel
    )
}

/// Concrete implementation for launching data import flows.
///
/// Manages the presentation of data import dialogs with support for sync feature
/// integration and customizable UI configurations. Handles the coordination between
/// data import functionality and sync features when available.
final class DataImportFlowLauncher: DataImportFlowRelaunching {
    private let pinningManager: PinningManager

    init(pinningManager: PinningManager) {
        self.pinningManager = pinningManager
    }

    @MainActor
    func relaunchDataImport(
        model: DataImportViewModel
    ) {
        DataImportView(
            model: model,
            importFlowLauncher: self,
            syncFeatureVisibility: syncFeatureVisibility,
            pinningManager: pinningManager
        ).show()
    }

    @MainActor
    func launchDataImport(
        title: String = UserText.importDataTitle,
        isDataTypePickerExpanded: Bool,
        in window: NSWindow? = nil,
        onFinished: @escaping () -> Void = {},
        onCancelled: @escaping () -> Void = {},
        completion: (() -> Void)? = nil
    ) {
        let viewModel = DataImportViewModel(
            syncFeatureVisibility: syncFeatureVisibility,
            onFinished: onFinished,
            onCancelled: onCancelled
        )
        DataImportView(
            model: viewModel,
            importFlowLauncher: self,
            syncFeatureVisibility: syncFeatureVisibility,
            pinningManager: pinningManager
        ).show(in: window, completion: completion)
    }

    @MainActor
    private var syncFeatureVisibility: SyncFeatureVisibility {
        let ddgSync = NSApp.delegateTyped.syncService
        let featureFlagger = NSApp.delegateTyped.featureFlagger
        if
            case .inactive = ddgSync?.authState,
            let deviceSyncLauncher = DeviceSyncCoordinator(),
            featureFlagger.isNewSyncEntryPointsFeatureOn {
            return .show(syncLauncher: deviceSyncLauncher)
        } else {
            return .hide
        }
    }
}
