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

/// Protocol for re-launching legacy data import flows from within legacy data import
///
/// Provides functionality to initiate data import flows with customizable
/// presentation options and data type selection.
protocol LegacyDataImportFlowRelaunching {
    /// Launches the data import flow with the specified configuration
    /// - Parameters:
    ///   - model: The view model containing import data and state
    ///   - title: The title to display in the import dialog
    ///   - isDataTypePickerExpanded: Whether the data type picker should start expanded
    @MainActor
    func relaunchDataImport(
        model: LegacyDataImportViewModel,
        title: String,
        isDataTypePickerExpanded: Bool
    )
}

/// Concrete implementation for launching data import flows.
///
/// Manages the presentation of data import dialogs with support for sync feature
/// integration and customizable UI configurations. Handles the coordination between
/// data import functionality and sync features when available.
final class DataImportFlowLauncher: LegacyDataImportFlowRelaunching, DataImportFlowRelaunching {
    @MainActor
    func relaunchDataImport(
        model: DataImportViewModel
    ) {
        DataImportView(
            model: model,
            importFlowLauncher: self,
            syncFeatureVisibility: syncFeatureVisibility
        ).show()
    }

    @MainActor
    func relaunchDataImport(
        model: LegacyDataImportViewModel,
        title: String,
        isDataTypePickerExpanded: Bool
    ) {
        LegacyDataImportView(
            model: model,
            importFlowLauncher: self,
            title: title,
            isDataTypePickerExpanded: isDataTypePickerExpanded,
            syncFeatureVisibility: syncFeatureVisibility
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
        let featureFlagger = NSApp.delegateTyped.featureFlagger
        guard featureFlagger.isFeatureOn(.dataImportNewExperience) else {
            let viewModel = LegacyDataImportViewModel(onFinished: onFinished, onCancelled: onCancelled)
            LegacyDataImportView(
                model: viewModel,
                importFlowLauncher: self,
                title: title,
                isDataTypePickerExpanded: isDataTypePickerExpanded,
                syncFeatureVisibility: syncFeatureVisibility
            ).show(in: window, completion: completion)
            return
        }
        let viewModel = DataImportViewModel(
            syncFeatureVisibility: syncFeatureVisibility,
            onFinished: onFinished,
            onCancelled: onCancelled
        )
        DataImportView(
            model: viewModel,
            importFlowLauncher: self,
            syncFeatureVisibility: syncFeatureVisibility
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
