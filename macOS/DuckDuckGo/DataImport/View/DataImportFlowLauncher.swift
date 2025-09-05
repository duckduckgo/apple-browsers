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

/// Protocol for launching data import flows.
///
/// Provides functionality to initiate data import flows with customizable
/// presentation options and data type selection.
protocol DataImportFlowLaunching {
    /// Launches the data import flow with the specified configuration
    /// - Parameters:
    ///   - model: The view model containing import data and state
    ///   - title: The title to display in the import dialog
    ///   - isDataTypePickerExpanded: Whether the data type picker should start expanded
    @MainActor
    func launchDataImport(
        model: DataImportViewModel,
        title: String,
        isDataTypePickerExpanded: Bool
    )
}

/// Concrete implementation for launching data import flows.
///
/// Manages the presentation of data import dialogs with support for sync feature
/// integration and customizable UI configurations. Handles the coordination between
/// data import functionality and sync features when available.
final class DataImportFlowLauncher: DataImportFlowLaunching {
    @MainActor
    func launchDataImport(
        model: DataImportViewModel,
        title: String,
        isDataTypePickerExpanded: Bool
    ) {
        launchDataImport(model: model, title: title, isDataTypePickerExpanded: isDataTypePickerExpanded, in: nil)
    }

    @MainActor
    func launchDataImport(
        model: DataImportViewModel = DataImportViewModel(),
        title: String = UserText.importDataTitle,
        isDataTypePickerExpanded: Bool,
        in window: NSWindow? = nil,
        completion: (() -> Void)? = nil
    ) {
        let ddgSync = NSApp.delegateTyped.syncService
        let syncFeatureVisibility: DataImportView.SyncFeatureVisibility
        let featureFlagger = NSApp.delegateTyped.featureFlagger
        if
            case .inactive = ddgSync?.authState,
            let deviceSyncLauncher = DeviceSyncCoordinator(),
            featureFlagger.isNewSyncEntryPointsFeatureOn {
            syncFeatureVisibility = .show(syncLauncher: deviceSyncLauncher)
        } else {
            syncFeatureVisibility = .hide
        }
        DataImportView(
            model: model,
            importFlowLauncher: self,
            title: title,
            isDataTypePickerExpanded: isDataTypePickerExpanded,
            syncFeatureVisibility: syncFeatureVisibility
        ).show(in: window, completion: completion)
    }
}
