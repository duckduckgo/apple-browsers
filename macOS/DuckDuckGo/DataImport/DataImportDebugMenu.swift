//
//  DataImportDebugMenu.swift
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

import AppKit
import Persistence

struct DataImportDebugSettings: StoringKeys {
    let forcesMacOS27PermissionsFix = StorageKey<Bool>(.dataImportForceMacOS27PermissionsFix)
}

extension KeyedStoring where Keys == DataImportDebugSettings {

    /// Non-optional accessor for the underlying optional storage value: absent means "not forced".
    var isForcingMacOS27PermissionsFix: Bool {
        get {
            self.forcesMacOS27PermissionsFix ?? false
        }
        nonmutating set {
            self.forcesMacOS27PermissionsFix = newValue
        }
    }
}

/// `Debug → Data Import` submenu.
final class DataImportDebugMenu: NSMenu, NSMenuDelegate {

    private let settings: any KeyedStoring<DataImportDebugSettings> = UserDefaults.standard.keyedStoring()
    private let pinningManager: PinningManager

    private let forceMacOS27PermissionsFixMenuItem = NSMenuItem(title: "Force macOS 27 Permissions Fix", action: #selector(toggleForceMacOS27PermissionsFix))
    private let keychainPermissionsMenuItem = NSMenuItem(title: "Show Keychain Permissions Prompt", action: #selector(showKeychainPermissionsPrompt))

    init(title: String, pinningManager: PinningManager) {
        self.pinningManager = pinningManager
        super.init(title: title)
        self.delegate = self
        buildItems {
            forceMacOS27PermissionsFixMenuItem.targetting(self)
            keychainPermissionsMenuItem.targetting(self)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        forceMacOS27PermissionsFixMenuItem.state = settings.isForcingMacOS27PermissionsFix ? .on : .off
    }

    @objc
    private func toggleForceMacOS27PermissionsFix(_ sender: NSMenuItem) {
        settings.isForcingMacOS27PermissionsFix.toggle()
    }

    @MainActor
    @objc
    private func showKeychainPermissionsPrompt(_ sender: NSMenuItem) {
        DataImportFlowLauncher(pinningManager: pinningManager)
            .launchDataImport(at: .passwordEntryHelp)
    }
}
