//
//  AttributedMetricDebugMenu.swift
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
import AttributedMetric
import Common
import Foundation

final class AttributedMetricDebugMenu: NSMenu, NSMenuDelegate {

    private var attributedMetricDataStorage: any AttributedMetricDataStoring

    init() {
        self.attributedMetricDataStorage = AttributedMetricDataStorage(userDefaults: .appConfiguration, errorHandler: nil)

        super.init(title: "Attributed Metrics")

        self.delegate = self
        buildMenuItems()
    }

    private func buildMenuItems() {
        removeAllItems()

        buildItems {
            NSMenuItem(title: "Reset Stored Data", action: #selector(AttributedMetricDebugMenu.resetAllData))
                .targetting(self)

            NSMenuItem(title: "Set Current Time...", action: #selector(AttributedMetricDebugMenu.setCurrentTime))
                .targetting(self)

            NSMenuItem(title: "Set Origin...", action: #selector(AttributedMetricDebugMenu.setOrigin))
                .targetting(self)

            NSMenuItem.separator()

            NSMenuItem(title: "Install Date: \(formatOptionalDate(attributedMetricDataStorage.installDate))")

            NSMenuItem(title: "Last Retention Threshold: \(attributedMetricDataStorage.lastRetentionThreshold?.description ?? "nil")")

            NSMenuItem(title: "Debug Origin: \(attributedMetricDataStorage.debugOrigin ?? "nil")")

            NSMenuItem.separator()

            NSMenuItem(title: "Search (8 days): \(attributedMetricDataStorage.search8Days.debugDescription)")

            NSMenuItem(title: "Ad Click (8 days): \(attributedMetricDataStorage.adClick8Days.debugDescription)")

            NSMenuItem(title: "Duck AI Chat (8 days): \(attributedMetricDataStorage.duckAIChat8Days.debugDescription)")

            NSMenuItem.separator()

            NSMenuItem(title: "Subscription Date: \(formatOptionalDate(attributedMetricDataStorage.subscriptionDate))")

            NSMenuItem(title: "Subscription Free Trial Fired: \(String(attributedMetricDataStorage.subscriptionFreeTrialFired))")

            NSMenuItem(title: "Subscription Month1 Fired: \(String(attributedMetricDataStorage.subscriptionMonth1Fired))")

            NSMenuItem(title: "Sync Devices Count: \(String(attributedMetricDataStorage.syncDevicesCount))")
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenuItems()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Formatting Helpers

    private func formatOptionalDate(_ date: Date?) -> String {
        guard let date = date else { return "nil" }
        if #available(macOS 12.0, *) {
            return date.ISO8601Format()
        } else {
            return date.debugDescription
        }
    }

    // MARK: - Actions

    @objc private func resetAllData(_ sender: Any?) {
        Task { @MainActor in
            guard case .alertFirstButtonReturn = await NSAlert.resetAttributedMetricsAlert().runModal() else { return }

            attributedMetricDataStorage.removeAll()

            await NSAlert.attributedMetricsResetCompleteAlert().runModal()
        }
    }

    @objc private func setCurrentTime(_ sender: Any?) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Set Current Time"
            alert.informativeText = "Select a date and time to override the current time for testing:"
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")

            let datePicker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
            datePicker.datePickerStyle = .textFieldAndStepper
            datePicker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
            datePicker.dateValue = attributedMetricDataStorage.debugDate ?? Date()

            alert.accessoryView = datePicker

            let response = await alert.runModal()

            switch response {
            case .alertFirstButtonReturn:
                let selectedDate = datePicker.dateValue
                attributedMetricDataStorage.debugDate = selectedDate

                let confirmAlert = NSAlert()
                confirmAlert.messageText = "Done"
                confirmAlert.informativeText = "Current time set to: \(formatOptionalDate(selectedDate))\n**RESTART THE APP TO APPLY**"
                confirmAlert.addButton(withTitle: "OK")
                await confirmAlert.runModal()

            case .alertSecondButtonReturn:
                attributedMetricDataStorage.debugDate = nil

                let confirmAlert = NSAlert()
                confirmAlert.messageText = "Done"
                confirmAlert.informativeText = "Current time override removed"
                confirmAlert.addButton(withTitle: "OK")
                await confirmAlert.runModal()

            default:
                break
            }
        }
    }

    @objc private func setOrigin(_ sender: Any?) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Set Origin"
            alert.informativeText = "Enter origin value:"
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            if let currentOrigin = attributedMetricDataStorage.debugOrigin {
                textField.stringValue = currentOrigin
            }
            alert.accessoryView = textField

            let response = await alert.runModal()

            if response == .alertFirstButtonReturn {
                let origin = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

                if origin.isEmpty {
                    attributedMetricDataStorage.debugOrigin = nil
                } else {
                    attributedMetricDataStorage.debugOrigin = origin
                }

                let confirmAlert = NSAlert()
                confirmAlert.messageText = "Done"
                confirmAlert.informativeText = "Origin set to: \(origin.isEmpty ? "(empty)" : origin)"
                confirmAlert.addButton(withTitle: "OK")
                await confirmAlert.runModal()
            }
        }
    }
}

// MARK: - NSAlert Extensions

extension NSAlert {
    static func resetAttributedMetricsAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Reset Attributed Metrics Data"
        alert.informativeText = "Are you sure you want to remove all Attributed Metrics data stored in UserDefaults? This action cannot be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert
    }

    static func attributedMetricsResetCompleteAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Done"
        alert.informativeText = "All Attributed Metrics data stored in UserDefaults has been removed"
        alert.addButton(withTitle: "OK")
        return alert
    }
}
