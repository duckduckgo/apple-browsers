//
//  ReinstallUserDetectionDebugMenu.swift
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
import Common
import Foundation
import Persistence

final class ReinstallUserDetectionDebugMenu: NSMenu, NSMenuDelegate {

    private let reinstallUserDetection: ReinstallingUserDetecting
    private let keyValueStore: ThrowingKeyValueStoring
    private let fileManager: FileManager

    init(
        keyValueStore: ThrowingKeyValueStoring = NSApp.delegateTyped.keyValueStore,
        fileManager: FileManager = .default
    ) {
        self.keyValueStore = keyValueStore
        self.reinstallUserDetection = DefaultReinstallUserDetection(keyValueStore: keyValueStore)
        self.fileManager = fileManager
        super.init(title: "Reinstall Detection")
        self.delegate = self
        buildMenuItems()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildMenuItems() {
        removeAllItems()

#if SPARKLE
        let isReinstall = reinstallUserDetection.isReinstallingUser
        let storedDate = try? keyValueStore.object(forKey: "reinstall.detection.bundle-creation-date") as? Date
        let currentDate = getBundleCreationDate()

        buildItems {
            NSMenuItem(title: "Build: Sparkle (detection enabled)")

            NSMenuItem.separator()

            NSMenuItem(title: "Is Reinstalling User: \(isReinstall ? "Yes" : "No")")

            NSMenuItem.separator()

            NSMenuItem(title: "Current Bundle Creation Date:")
            NSMenuItem(title: "  \(formatDate(currentDate))")

            NSMenuItem(title: "Stored Bundle Creation Date:")
            NSMenuItem(title: "  \(formatDate(storedDate))")

            NSMenuItem.separator()

            NSMenuItem(title: "Reset Detection State", action: #selector(resetDetectionState))
                .targetting(self)
        }
#else
        buildItems {
            NSMenuItem(title: "Build: App Store (detection disabled)")

            NSMenuItem.separator()

            NSMenuItem(title: "Reinstall detection is not supported")
            NSMenuItem(title: "for App Store builds.")
        }
#endif
    }

#if SPARKLE
    private func getBundleCreationDate() -> Date? {
        let bundleURL = Bundle.main.bundleURL
        do {
            let attributes = try fileManager.attributesOfItem(atPath: bundleURL.path)
            return attributes[.creationDate] as? Date
        } catch {
            return nil
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Not set" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    @objc private func resetDetectionState(_ sender: Any?) {
        try? keyValueStore.removeObject(forKey: "reinstall.detection.bundle-creation-date")
        try? keyValueStore.removeObject(forKey: "reinstall.detection.is-reinstalling-user")

        let alert = NSAlert()
        alert.messageText = "Detection State Reset"
        alert.informativeText = "Reinstall detection state has been cleared. Restart the app to re-run detection."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
#endif

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenuItems()
    }
}
