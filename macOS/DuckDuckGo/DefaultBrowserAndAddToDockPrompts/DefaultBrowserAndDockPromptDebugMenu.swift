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
    private let simulatedTodayDateMenuItem = NSMenuItem(title: "")
    private let popoverWillShowDateMenuItem = NSMenuItem(title: "")
    private let bannerWillShowDateMenuItem = NSMenuItem(title: "")
    private let promptPermanentlyDismissedMenuItem = NSMenuItem(title: "")
    private let numberOfBannersShownMenuItem = NSMenuItem(title: "")
    private let store = NSApp.delegateTyped.defaultBrowserAndDockPromptKeyValueStore
    private let debugStore = DefaultBrowserAndDockPromptDebugStore()
    private let defaultBrowserAndDockPromptFeatureFlagger = NSApp.delegateTyped.defaultBrowserAndDockPromptFeatureFlagger
    private let localStatisticsStore = LocalStatisticsStore()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = .current
        return formatter
    }()

    init() {
        super.init(title: "")

        guard defaultBrowserAndDockPromptFeatureFlagger.isDefaultBrowserAndDockPromptFeatureEnabled else { return }

        buildItems {
            NSMenuItem(title: "Override Today's Date", action: #selector(simulateCurrentDate))
                .targetting(self)
            NSMenuItem(title: "Reset Prompts And Today's Date", action: #selector(resetPrompts))
                .targetting(self)
            simulatedTodayDateMenuItem
            popoverWillShowDateMenuItem
            bannerWillShowDateMenuItem
            numberOfBannersShownMenuItem
            promptPermanentlyDismissedMenuItem
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    override func update() {
        updateMenuItemsState()
    }

    @objc func simulateCurrentDate() {
        showDatePickerAlert { [weak self] date in
            guard let self, let date else { return }
            debugStore.simulatedTodayDate = date
        }
    }

    @objc func resetPrompts() {
        debugStore.reset()
        store.popoverShownDate = nil
        store.bannerShownDate = nil
        store.isBannerPermanentlyDismissed = false
        updateMenuItemsState()
    }

    private func updateMenuItemsState() {

        func updatePopoverMenuInfo() {
            if let popoverShownDate = store.popoverShownDate {
                let popoverShownDate = Date(timeIntervalSince1970: popoverShownDate)
                popoverWillShowDateMenuItem.title = "Popover prompt has shown: \(Self.dateFormatter.string(from: popoverShownDate))"
            } else {
                let popoverWillShowDate = localStatisticsStore.installDate
                    .flatMap { $0.addingTimeInterval(.days(defaultBrowserAndDockPromptFeatureFlagger.firstPopoverDelayDays)) }

                let formattedWillShowDate = popoverWillShowDate.flatMap { Self.dateFormatter.string(from: $0) } ?? "N/A"
                popoverWillShowDateMenuItem.title = "Popover prompt will show: \(formattedWillShowDate)"
            }
        }

        func updateBannerMenuInfo() {
            promptPermanentlyDismissedMenuItem.title = "Prompt hasn't been permanently dismissed."
            numberOfBannersShownMenuItem.title = "Number Of Banners Shown: \(store.bannerShownOccurrences)"

            // If the popover hasn't been shown inform that the banner will show x days after popover
            guard let popoverShownDate = store.popoverShownDate else {
                bannerWillShowDateMenuItem.title = "First Banner will show \(defaultBrowserAndDockPromptFeatureFlagger.firstPopoverDelayDays) days after seeing the popover."
                return
            }

            guard !store.isBannerPermanentlyDismissed else {
                bannerWillShowDateMenuItem.title = "Banner will not show again."
                promptPermanentlyDismissedMenuItem.title = "Banner has been permanently dismissed."
                return
            }

            // If the first banner has shown inform next banner will be shown at date.
            // Else if the first banner hasn't been show inform first banner will be shown at date
            if let bannerShownDate = store.bannerShownDate {
                let lastBannerDate = Date(timeIntervalSince1970: bannerShownDate)
                let nextBannerDate = lastBannerDate.addingTimeInterval(.days(defaultBrowserAndDockPromptFeatureFlagger.bannerRepeatIntervalDays))
                bannerWillShowDateMenuItem.title = "Next Banner will show: \(Self.dateFormatter.string(from: nextBannerDate))"
            } else {
                let popoverDate = Date(timeIntervalSince1970: popoverShownDate)
                let firstBannerDate = popoverDate.addingTimeInterval(.days(defaultBrowserAndDockPromptFeatureFlagger.bannerAfterPopoverDelayDays))
                bannerWillShowDateMenuItem.title = "First Banner will show \(Self.dateFormatter.string(from: firstBannerDate))"
            }
        }

        simulatedTodayDateMenuItem.title = "Today's Date: \(Self.dateFormatter.string(from: debugStore.simulatedTodayDate))"

        // Update Popover Menu Info
        updatePopoverMenuInfo()

        // Update Banner Info
        updateBannerMenuInfo()
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
        datePicker.dateValue = debugStore.simulatedTodayDate
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
