//
//  WinBackOfferDebugMenu.swift
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
import Subscription
import Persistence

final class WinBackOfferDebugMenu: NSMenuItem {

    private var winbackOfferStore: any WinbackOfferStoring
    private let debugStore = WinBackOfferDebugStore()

    private let simulatedTodayDateMenuItem = NSMenuItem(title: "")
    private let churnDateMenuItem = NSMenuItem(title: "")
    private let offerStartDateMenuItem = NSMenuItem(title: "")
    private let offerEndDateMenuItem = NSMenuItem(title: "")
    private let modalPresentationDateMenuItem = NSMenuItem(title: "")
    private let urgencyMessageDateMenuItem = NSMenuItem(title: "")
    private let storageStateMenuItem = NSMenuItem(title: "")

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = .current
        return formatter
    }()

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(winbackOfferStore: any WinbackOfferStoring) {
        self.winbackOfferStore = winbackOfferStore
        super.init(title: "Win-back Offer", action: nil, keyEquivalent: "")
        self.submenu = makeSubmenu()
    }

    private func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")

        menu.addItem(NSMenuItem(title: "Simulate Churn", action: #selector(simulateChurn), target: self))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Override Today's Date", action: #selector(overrideTodaysDate), target: self))
        menu.addItem(NSMenuItem(title: "Reset Win-back Offer", action: #selector(resetWinBackOffer), target: self))
        menu.addItem(.separator())

        menu.addItem(simulatedTodayDateMenuItem)
        menu.addItem(churnDateMenuItem)
        menu.addItem(offerStartDateMenuItem)
        menu.addItem(offerEndDateMenuItem)
        menu.addItem(modalPresentationDateMenuItem)
        menu.addItem(urgencyMessageDateMenuItem)
        menu.addItem(storageStateMenuItem)

        menu.delegate = self
        return menu
    }

    // MARK: - Menu Actions

    @objc
    func simulateChurn() {
        let effectiveDate = debugStore.simulatedTodayDate
        winbackOfferStore.storeChurnDate(effectiveDate)
        winbackOfferStore.setHasRedeemedOffer(false)
        winbackOfferStore.firstDayModalShown = false
        updateMenuItemsState()
    }

    @objc
    func overrideTodaysDate() {
        showDatePickerAlert { [weak self] date in
            guard let self, let date else { return }
            debugStore.simulatedTodayDate = date
            updateMenuItemsState()
        }
    }

    @objc
    func resetWinBackOffer() {
        debugStore.reset()
        winbackOfferStore.storeChurnDate(Date(timeIntervalSince1970: 0))
        winbackOfferStore.setHasRedeemedOffer(false)
        winbackOfferStore.firstDayModalShown = false
        updateMenuItemsState()
    }

    // MARK: - Menu State Update

    private func updateMenuItemsState() {
        let today = debugStore.simulatedTodayDate
        simulatedTodayDateMenuItem.title = "Today's Date: \(Self.dateFormatter.string(from: today))"

        guard let churnDate = winbackOfferStore.getChurnDate(),
              churnDate.timeIntervalSince1970 > 0 else {
            churnDateMenuItem.title = "Churn Date: Not set"
            offerStartDateMenuItem.title = "Offer Start Date: N/A"
            offerEndDateMenuItem.title = "Offer End Date: N/A"
            modalPresentationDateMenuItem.title = "Modal Presentation: N/A"
            urgencyMessageDateMenuItem.title = "Urgency Message: N/A"
            storageStateMenuItem.title = "Storage: No churn simulated"
            return
        }

        let offerStartDate = churnDate.addingTimeInterval(3 * 24 * 60 * 60) // 3 days after churn
        let offerEndDate = offerStartDate.addingTimeInterval(5 * 24 * 60 * 60) // 5 days availability
        let urgencyMessageDate = offerEndDate.addingTimeInterval(-1 * 24 * 60 * 60) // Last day

        churnDateMenuItem.title = "Churn Date: \(Self.dateFormatter.string(from: churnDate))"
        offerStartDateMenuItem.title = "Offer Start Date: \(Self.dateFormatter.string(from: offerStartDate))"
        offerEndDateMenuItem.title = "Offer End Date: \(Self.dateFormatter.string(from: offerEndDate))"
        modalPresentationDateMenuItem.title = "Modal Presentation: First launch during offer period"
        urgencyMessageDateMenuItem.title = "Urgency Message: \(Self.dateFormatter.string(from: urgencyMessageDate))"

        let hasRedeemed = winbackOfferStore.hasRedeemedOffer()
        let modalShown = winbackOfferStore.firstDayModalShown
        storageStateMenuItem.title = "Storage: Redeemed=\(hasRedeemed), ModalShown=\(modalShown)"
    }

    private func showDatePickerAlert(onValueChange: @escaping (Date?) -> Void) {
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
        let selectedDatePlusOneHour = selectedDate.addingTimeInterval(TimeInterval.hours(1))
        onValueChange(selectedDatePlusOneHour)
    }
}

extension WinBackOfferDebugMenu: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateMenuItemsState()
    }
}

final class WinBackOfferDebugStore {
    @UserDefaultsWrapper(key: .debugWinBackOfferSimulatedTodayDate, defaultValue: Date())
    var simulatedTodayDate: Date

    init() {}

    func reset() {
        simulatedTodayDate = Date()
    }
}
