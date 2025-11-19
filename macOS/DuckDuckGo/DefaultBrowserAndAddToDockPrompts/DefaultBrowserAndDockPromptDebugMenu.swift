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

/// **DEBUG MENU for Default Browser & Dock Prompts**
///
/// This menu provides tools to test and debug the prompt system without waiting for real time delays.
/// Located in: Debug menu → "SAD/ATT Prompts (Default Browser/Add to Dock)"
///
/// **Menu Items:**
/// 1. **"Override Today's Date…"**: Opens date picker to simulate any date (fast-forward time)
/// 2. **"Advance by 14 Days"**: Quick jump forward by default delay interval
/// 3. **"Reset Prompts And Today's Date"**: Clear all prompt history and date override
/// 4. **Status displays** (read-only):
///    - Current simulated date (if overridden)
///    - When popover will show (or when it was shown)
///    - When first banner will show (or when it was shown)
///    - Number of times banner has been shown
///    - Whether banner was permanently dismissed
///    - Number of inactive days
///    - When inactive modal will show (or when it was shown)
///
/// **How to Test Prompts:**
/// 1. Use "Reset Prompts And Today's Date" to clear all state
/// 2. Use "Override Today's Date…" or "Advance by 14 Days" to fast-forward time
/// 3. Check status menu items to see when each prompt will appear
/// 4. Focus a main window to trigger prompt evaluation
///
/// **See also:**
/// - `DefaultBrowserAndDockPromptTypeDecider.ActiveUser` - timing rules for popover/banner
/// - `DefaultBrowserAndDockPromptTypeDecider.InactiveUser` - timing rules for inactive modal
/// - `DefaultBrowserAndDockPromptDebugStore` - stores simulated date override
final class DefaultBrowserAndDockPromptDebugMenu: NSMenu {
    private let overrideDateMenuItem = NSMenuItem(title: "", action: #selector(simulateCurrentDate))
    private let simulatedTodayDateMenuItem = NSMenuItem(title: "")
    private let popoverWillShowDateMenuItem = NSMenuItem(title: "")
    private let bannerWillShowDateMenuItem = NSMenuItem(title: "")
    private let promptPermanentlyDismissedMenuItem = NSMenuItem(title: "")
    private let numberOfBannersShownMenuItem = NSMenuItem(title: "")
    private let inactiveDaysMenuItem = NSMenuItem(title: "")
    private let inactiveWillShowDateMenuItem = NSMenuItem(title: "")
    private let store = NSApp.delegateTyped.defaultBrowserAndDockPromptService.store
    private let debugStore = DefaultBrowserAndDockPromptDebugStore()
    private let defaultBrowserAndDockPromptFeatureFlagger = NSApp.delegateTyped.defaultBrowserAndDockPromptService.featureFlagger
    private let localStatisticsStore = LocalStatisticsStore()
    private let userActivityManager = NSApp.delegateTyped.defaultBrowserAndDockPromptService.userActivityManager
    private let userActivityStore = NSApp.delegateTyped.defaultBrowserAndDockPromptService.userActivityManager.store

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = .current
        return formatter
    }()

    init() {
        super.init(title: "")

        guard defaultBrowserAndDockPromptFeatureFlagger.isDefaultBrowserAndDockPromptForActiveUsersFeatureEnabled || defaultBrowserAndDockPromptFeatureFlagger.isDefaultBrowserAndDockPromptForInactiveUsersFeatureEnabled else { return }

        overrideDateMenuItem.target = self

        buildItems {
            overrideDateMenuItem
            NSMenuItem(title: "Advance by 14 Days", action: #selector(advanceBy14Days))
                .targetting(self)
            NSMenuItem(title: "Reset Prompts And Today's Date", action: #selector(resetPrompts))
                .targetting(self)
            NSMenuItem.separator()
            simulatedTodayDateMenuItem
            popoverWillShowDateMenuItem
            bannerWillShowDateMenuItem
            numberOfBannersShownMenuItem
            promptPermanentlyDismissedMenuItem
            inactiveDaysMenuItem
            inactiveWillShowDateMenuItem
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    override func update() {
        updateMenuItemsState()
    }

    /// **DATE SIMULATION**
    ///
    /// Opens a date picker alert to override "today's date" for testing.
    /// This allows fast-forwarding time to trigger prompts without waiting.
    ///
    /// **How it works:**
    /// - Stores override date in `DefaultBrowserAndDockPromptDebugStore.simulatedTodayDate`
    /// - All date calculations use this override instead of `Date()` (see `DefaultBrowserAndDockPromptService`)
    /// - Also records user activity to prevent inactive modal from showing
    ///
    /// **Use cases:**
    /// - Jump 14 days ahead to see popover (after install)
    /// - Jump 28 days ahead to see first banner (14 days install + 14 days after popover)
    /// - Jump forward to test banner repeat intervals
    ///
    /// **See also:**
    /// - `advanceBy14Days()` - quick jump by default delay interval
    /// - `DefaultBrowserAndDockPromptDebugStore` - stores the override
    @objc func simulateCurrentDate() {
        let result = showDatePickerAlert()

        switch result {
        case .success(.some(let date)):
            // OK clicked - set new override date
            debugStore.simulatedTodayDate = date
            userActivityManager.recordActivity()
            updateMenuItemsState()
        case .success(.none):
            // Reset clicked - clear the override
            debugStore.simulatedTodayDate = nil
            updateMenuItemsState()
        case .failure:
            // Cancel clicked - do nothing
            break
        }
    }

    /// **RESET ALL PROMPT STATE**
    ///
    /// Clears all prompt history and date overrides to start fresh testing.
    ///
    /// **What gets reset:**
    /// - Simulated date override (back to real current date)
    /// - Popover shown date
    /// - Banner shown date and occurrences
    /// - Inactive modal shown date
    /// - Permanent dismissal flag
    /// - User activity (sets to "active today")
    ///
    /// **After reset:**
    /// - Popover will show after 14 days from install (use date simulation to fast-forward)
    /// - All prompt counters reset to zero
    /// - User is considered "active" (won't trigger inactive modal)
    @objc func resetPrompts() {
        debugStore.reset()
        store.popoverShownDate = nil
        store.bannerShownDate = nil
        store.inactiveUserModalShownDate = nil
        store.isBannerPermanentlyDismissed = false
        userActivityStore.save(DefaultBrowserAndDockPromptUserActivity(lastActiveDate: Date()))
        updateMenuItemsState()
    }

    /// Updates all menu item titles to reflect current state and calculated dates.
    /// Called when menu opens (via `update()`) and after state changes (reset, date override).
    private func updateMenuItemsState() {

        /// Updates the popover menu item to show either:
        /// - When it was shown (if already seen)
        /// - When it will show (install date + 14 days default)
        func updatePopoverMenuInfo() {
            if let popoverShownDate = store.popoverShownDate {
                // Popover already shown → display when it was shown
                let popoverShownDate = Date(timeIntervalSince1970: popoverShownDate)
                popoverWillShowDateMenuItem.title = "Popover prompt has shown: \(Self.dateFormatter.string(from: popoverShownDate))"
            } else {
                // Popover not shown yet → calculate when it will show (install date + delay)
                let popoverWillShowDate = localStatisticsStore.installDate
                    .flatMap { $0.addingTimeInterval(.days(defaultBrowserAndDockPromptFeatureFlagger.firstPopoverDelayDays)) }

                let formattedWillShowDate = popoverWillShowDate.flatMap { Self.dateFormatter.string(from: $0) } ?? "N/A"
                popoverWillShowDateMenuItem.title = "Popover prompt will show: \(formattedWillShowDate)"
            }
        }

        /// Updates banner-related menu items to show:
        /// - Number of times banner has been shown
        /// - Whether banner was permanently dismissed
        /// - When first/next banner will show (based on popover/last banner date)
        func updateBannerMenuInfo() {
            promptPermanentlyDismissedMenuItem.title = "Prompt hasn't been permanently dismissed."
            numberOfBannersShownMenuItem.title = "Number Of Banners Shown: \(store.bannerShownOccurrences)"

            // If the popover hasn't been shown inform that the banner will show x days after popover
            guard let popoverShownDate = store.popoverShownDate else {
                // Popover not shown yet → banner can't show until popover is seen
                bannerWillShowDateMenuItem.title = "First Banner will show \(defaultBrowserAndDockPromptFeatureFlagger.bannerAfterPopoverDelayDays) days after seeing the popover."
                return
            }

            guard !store.isBannerPermanentlyDismissed else {
                // User clicked "Never Ask Again" → no more banners
                bannerWillShowDateMenuItem.title = "Banner will not show again."
                promptPermanentlyDismissedMenuItem.title = "Banner has been permanently dismissed."
                return
            }

            // If the first banner has shown inform next banner will be shown at date.
            // Else if the first banner hasn't been show inform first banner will be shown at date
            if let bannerShownDate = store.bannerShownDate {
                // Banner already shown at least once → calculate next repeat (last banner + repeat interval)
                let lastBannerDate = Date(timeIntervalSince1970: bannerShownDate)
                let nextBannerDate = lastBannerDate.addingTimeInterval(.days(defaultBrowserAndDockPromptFeatureFlagger.bannerRepeatIntervalDays))
                bannerWillShowDateMenuItem.title = "Next Banner will show: \(Self.dateFormatter.string(from: nextBannerDate))"
            } else {
                // Banner never shown → calculate first banner (popover date + delay)
                let popoverDate = Date(timeIntervalSince1970: popoverShownDate)
                let firstBannerDate = popoverDate.addingTimeInterval(.days(defaultBrowserAndDockPromptFeatureFlagger.bannerAfterPopoverDelayDays))
                bannerWillShowDateMenuItem.title = "First Banner will show \(Self.dateFormatter.string(from: firstBannerDate))"
            }
        }

        /// Updates inactive user modal menu items to show:
        /// - Current number of inactive days
        /// - When modal was shown (if already seen) or when it will show
        ///
        /// Inactive modal requires TWO conditions:
        /// 1. ≥28 days since install (default)
        /// 2. ≥7 days of inactivity (default)
        func updateInactiveUserModalMenuInfo() {
            // Record current activity (so opening this menu doesn't count as inactivity)
            userActivityManager.recordActivity()
            let inactiveDays = userActivityManager.numberOfInactiveDays()
            inactiveDaysMenuItem.title = "Number of inactive days: \(inactiveDays)"

            if let inactiveShownDate = store.inactiveUserModalShownDate {
                // Modal already shown → display when it was shown
                let inactiveShownDate = Date(timeIntervalSince1970: inactiveShownDate)
                inactiveWillShowDateMenuItem.title = "Inactive User prompt has shown: \(Self.dateFormatter.string(from: inactiveShownDate))"
            } else if store.isBannerPermanentlyDismissed {
                // Banner permanently dismissed → inactive modal won't show either
                inactiveWillShowDateMenuItem.title = "Inactive User prompt will not be shown."
            } else if let installDate = localStatisticsStore.installDate {
                // Calculate when modal will show based on two criteria:
                // 1. Install date + 28 days (default)
                let firstDateAfterInstall = installDate.advanced(by: .days(defaultBrowserAndDockPromptFeatureFlagger.inactiveModalNumberOfDaysSinceInstall))
                // 2. Today + 7 days of inactivity (default)
                let nextDateAfterInactivity = (debugStore.simulatedTodayDate ?? Date()).advanced(by: .days(defaultBrowserAndDockPromptFeatureFlagger.inactiveModalNumberOfInactiveDays + 1))

                let installDateCriteriaMet = (debugStore.simulatedTodayDate ?? Date()) >= firstDateAfterInstall
                let inactiveDaysCriteriaMet = inactiveDays >= defaultBrowserAndDockPromptFeatureFlagger.inactiveModalNumberOfInactiveDays

                var inactiveWillShowDate: Date?
                switch (installDateCriteriaMet, inactiveDaysCriteriaMet) {
                case (true, true):
                    // Both criteria met → can show today
                    inactiveWillShowDate = debugStore.simulatedTodayDate ?? Date()
                case (true, false):
                    // Install age met, but not inactive long enough → need more inactivity
                    inactiveWillShowDate = nextDateAfterInactivity
                case (false, _):
                    // Install age not met → need to wait for both criteria
                    inactiveWillShowDate = max(firstDateAfterInstall, nextDateAfterInactivity)
                }

                let formattedWillShowDate = inactiveWillShowDate.flatMap { Self.dateFormatter.string(from: $0) } ?? "N/A"
                inactiveWillShowDateMenuItem.title = "Inactive User prompt will show: \(formattedWillShowDate)"
            } else {
                inactiveWillShowDateMenuItem.title = "N/A"
            }
        }

        let currentOverride = debugStore.simulatedTodayDate

        if let currentOverride {
            overrideDateMenuItem.title = "Override Today's Date… (Currently: \(Self.dateFormatter.string(from: currentOverride)))"
        } else {
            overrideDateMenuItem.title = "Override Today's Date…"
        }

        simulatedTodayDateMenuItem.title = "Today's Date: \(Self.dateFormatter.string(from: debugStore.simulatedTodayDate ?? Date()))"

        // Update Popover Menu Info
        updatePopoverMenuInfo()

        // Update Banner Info
        updateBannerMenuInfo()

        // Update Inactive User Modal Info
        updateInactiveUserModalMenuInfo()
    }

    /// Displays a custom date picker alert for simulating "today's date".
    /// Features a calendar picker, localized text input, and "Today" quick button.
    /// The selected date overrides `Date()` throughout the prompt system for testing.
    ///
    /// - Returns: `Result<Date?, CancellationError>`
    ///   - `.success(date)` - OK clicked with selected date
    ///   - `.success(nil)` - Reset clicked (clear override)
    ///   - `.failure(CancellationError())` - Cancel clicked (no change)
    func showDatePickerAlert() -> Result<Date?, CancellationError> {
        let alert = NSAlert()
        alert.messageText = "Simulate Today's Date"

        let currentOverride = debugStore.simulatedTodayDate

        // Create localized date formatter with numeric format (e.g., "11/19/2025" for en_US, "19.11.2025" for de_DE)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: Locale.current)

        // Show current override status in alert
        if let currentOverride {
            alert.informativeText = "Currently overridden to: \(dateFormatter.string(from: currentOverride))"
        } else {
            alert.informativeText = "Currently using actual date"
        }

        // Three buttons: OK (confirm), Reset (clear override), Cancel
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        // Container holds all UI elements (text field, today button, calendar)
        let containerView = DatePickerContainer(frame: .init(x: 0, y: 0, width: 240, height: 210))

        // Text field: displays and accepts localized date input
        let textField = NSTextField(frame: .init(x: 0, y: 190, width: 170, height: 20))
        textField.formatter = dateFormatter
        textField.placeholderString = dateFormatter.string(from: Date())

        // "Today" button: quick reset to current real date
        let todayButton = NSButton(frame: .init(x: 175, y: 189, width: 65, height: 22))
        todayButton.title = "Today"
        todayButton.bezelStyle = .rounded
        todayButton.target = containerView
        todayButton.action = #selector(DatePickerContainer.todayButtonClicked(_:))

        // Calendar picker: visual date selection
        let calendarPicker = NSDatePicker(frame: .init(x: 0, y: 0, width: 240, height: 180))
        calendarPicker.datePickerStyle = .clockAndCalendar
        calendarPicker.datePickerElements = [.yearMonthDay]
        calendarPicker.dateValue = currentOverride ?? Date() // Start from current override or today
        calendarPicker.target = containerView
        calendarPicker.action = #selector(DatePickerContainer.calendarChanged(_:))

        // Two-way binding: text field ↔ calendar picker
        // When calendar changes → text updates (via binding)
        // When text changes → calendar updates (via binding)
        textField.bind(.value,
                      to: calendarPicker,
                      withKeyPath: "dateValue",
                      options: [.continuouslyUpdatesValue: true,
                               .nullPlaceholder: dateFormatter.string(from: Date())])

        // Store references so action handlers can access both controls
        containerView.textField = textField
        containerView.calendarPicker = calendarPicker

        containerView.addSubview(textField)
        containerView.addSubview(todayButton)
        containerView.addSubview(calendarPicker)
        alert.accessoryView = containerView

        // Show the alert and wait for user response
        let response = alert.runModal()

        if response == .alertSecondButtonReturn {
            // Reset button clicked → return success with nil to clear the override
            return .success(nil)
        }

        guard response == .alertFirstButtonReturn else {
            // Cancel button clicked → return failure
            return .failure(CancellationError())
        }

        // OK button clicked → return success with the selected date (add 1 hour to avoid midnight edge cases)
        let selectedDate = calendarPicker.dateValue
        let selectedDatePlusOneHour = selectedDate.addingTimeInterval(.hours(1))
        return .success(selectedDatePlusOneHour)
    }

    /// **QUICK TIME JUMP**
    ///
    /// Advances the simulated date by 14 days (the default delay interval for prompts).
    /// This is a convenience method to avoid manually picking dates.
    ///
    /// **Use cases:**
    /// - After reset, click once to reach popover eligibility (14 days from install)
    /// - After seeing popover, click once to reach first banner eligibility (14 days after popover)
    /// - After banner, click once to reach repeat banner eligibility (14 days after last banner)
    ///
    /// **Note:**
    /// - If no date override exists, starts from current real date
    /// - If date already overridden, adds 14 days to that override
    /// - Updates menu items to show new calculated dates
    ///
    /// **See also:**
    /// - `simulateCurrentDate()` - for custom date selection
    /// - `DefaultBrowserAndDockPromptFeatureFlagger` - defines the 14-day default intervals
    @objc private func advanceBy14Days() {
        let currentDate = debugStore.simulatedTodayDate ?? Date()
        let newDate = currentDate.addingTimeInterval(.days(14))
        debugStore.simulatedTodayDate = newDate
        updateMenuItemsState()
    }

}

/// Custom container view for the date picker alert.
/// Holds references to UI elements and provides action handlers for two-way binding.
private class DatePickerContainer: NSView {
    weak var textField: NSTextField?
    weak var calendarPicker: NSDatePicker?

    /// Called when user clicks a date in the calendar picker.
    /// Manually updates the text field to ensure synchronization (in addition to binding).
    @objc func calendarChanged(_ sender: NSDatePicker) {
        // Force text field to update from the calendar picker's new value
        textField?.objectValue = sender.dateValue
    }

    /// Called when user clicks the "Today" button.
    /// Sets both calendar and text field to the current real date.
    @objc func todayButtonClicked(_ sender: NSButton) {
        let today = Date()
        calendarPicker?.dateValue = today
        textField?.objectValue = today
    }
}

final class DefaultBrowserAndDockPromptDebugStore {
    @UserDefaultsWrapper(key: .debugSetDefaultAndAddToDockPromptCurrentDateKey)
    var simulatedTodayDate: Date?

    func reset() {
        simulatedTodayDate = nil
    }
}
