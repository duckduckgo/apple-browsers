//
//  DefaultBrowserAndDockPromptDebugMenu.swift
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

final class DefaultBrowserAndDockPromptDebugMenu: NSMenu {
    private let simulatedDateMenuItem = NSMenuItem(title: "")
    private let debugStorage = DefaultBrowserAndDockPromptDebugStore()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = .current
        return formatter
    }()

    init() {
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Simulate Today's Date", action: #selector(simulateCurrentDate))
                .targetting(self)
            NSMenuItem(title: "Reset Today's Date", action: #selector(resetSimulatedDate))
                .targetting(self)
            simulatedDateMenuItem
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    override func update() {
        updateWebUIMenuItemsState()
    }

    @objc func simulateCurrentDate() {
        showDatePickerAlert { [weak self] date in
            guard let self, let date else { return }
            debugStorage.simulatedTodayDate = date
        }
    }

    @objc func resetSimulatedDate() {
        debugStorage.reset()
        updateWebUIMenuItemsState()
    }

    private func updateWebUIMenuItemsState() {
        simulatedDateMenuItem.title = "Today's Date: \(Self.dateFormatter.string(from: debugStorage.simulatedTodayDate))"
    }

    func showDatePickerAlert(onValueChange: (Date?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Simulate Today's Date"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        // Create the date picker
        let datePicker = NSDatePicker(frame: .init(x: 0, y: 0, width: 200, height: 24))
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonth, .yearMonthDay]
        datePicker.dateValue = debugStorage.simulatedTodayDate
        alert.accessoryView = datePicker

        // Show the alert
        let response = alert.runModal()

        guard case .alertFirstButtonReturn = response else {
            onValueChange(nil)
            return
        }

        let selectedDate = datePicker.dateValue
        let selectedDatePlusOneHour = selectedDate.addingTimeInterval(.hours(1))
        onValueChange(selectedDatePlusOneHour)
    }

}

final class DefaultBrowserAndDockPromptDebugStore {
    @UserDefaultsWrapper(key: .debugSetDefaultAndAddToDockPromptCurrentDateKey, defaultValue: Date())
    var simulatedTodayDate: Date

    func reset() {
        simulatedTodayDate = Date()
    }
}
