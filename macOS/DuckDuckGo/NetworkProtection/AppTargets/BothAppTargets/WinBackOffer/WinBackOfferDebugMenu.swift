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
    private let debugStore: WinBackOfferDebugStore

    private let simulatedTodayDateMenuItem = NSMenuItem(title: "")
    private let churnDateMenuItem = NSMenuItem(title: "")
    private let eligibilityDateMenuItem = NSMenuItem(title: "")
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

    init(winbackOfferStore: any WinbackOfferStoring, keyValueStore: ThrowingKeyValueStoring) {
        self.winbackOfferStore = winbackOfferStore
        self.debugStore = WinBackOfferDebugStore(keyValueStore: keyValueStore)
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
        let markRedeemedItem = NSMenuItem(
            title: "Mark Offer Redeemed",
            action: #selector(markOfferRedeemed),
            target: self
        )
        menu.addItem(markRedeemedItem)
        let completeCooldownItem = NSMenuItem(
            title: "Complete Cooldown",
            action: #selector(completeCooldown),
            target: self
        )
        menu.addItem(completeCooldownItem)
        menu.addItem(.separator())
        menu.addItem(simulatedTodayDateMenuItem)
        menu.addItem(churnDateMenuItem)
        menu.addItem(eligibilityDateMenuItem)
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
        winbackOfferStore.storeOfferPresentationDate(nil)
        winbackOfferStore.didDismissUrgencyMessage = false
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
        winbackOfferStore.clearChurnDate()
        winbackOfferStore.setHasRedeemedOffer(false)
        winbackOfferStore.storeOfferPresentationDate(nil)
        winbackOfferStore.didDismissUrgencyMessage = false
        updateMenuItemsState()
    }

    @objc
    func markOfferRedeemed() {
        winbackOfferStore.setHasRedeemedOffer(true)
        winbackOfferStore.storeOfferPresentationDate(nil)
        winbackOfferStore.didDismissUrgencyMessage = false
        updateMenuItemsState()
    }

    @objc
    func completeCooldown() {
        let cooldownDuration = TimeInterval(.days(270))
        let availabilityOffset = TimeInterval.days(3)

        let cooldownExpiryDate = debugStore.simulatedTodayDate.addingTimeInterval(cooldownDuration)
        let firstDay = cooldownExpiryDate.addingTimeInterval(availabilityOffset)

        winbackOfferStore.storeChurnDate(cooldownExpiryDate)
        winbackOfferStore.setHasRedeemedOffer(false)
        winbackOfferStore.storeOfferPresentationDate(nil)
        winbackOfferStore.didDismissUrgencyMessage = false

        debugStore.simulatedTodayDate = firstDay
        updateMenuItemsState()
    }

    // MARK: - Menu State Update

    private func updateMenuItemsState() {
        let today = debugStore.simulatedTodayDate
        simulatedTodayDateMenuItem.title = "Today's Date: \(Self.dateFormatter.string(from: today))"

        guard let churnDate = winbackOfferStore.getChurnDate(),
              churnDate.timeIntervalSince1970 > 0 else {
            churnDateMenuItem.title = "Churn Date: Not set"
            eligibilityDateMenuItem.title = "Offer starts on: N/A"
            offerStartDateMenuItem.title = "Offer Window Start: N/A"
            offerEndDateMenuItem.title = "Offer Window Ends: N/A"
            modalPresentationDateMenuItem.title = "Launch Prompt Shown: No"
            urgencyMessageDateMenuItem.title = "Urgency message starts: N/A"
            storageStateMenuItem.title = "Storage: No churn simulated"
            return
        }

        churnDateMenuItem.title = "Churn Date: \(Self.dateFormatter.string(from: churnDate))"
        let eligibilityDate = churnDate.addingTimeInterval(3 * 24 * 60 * 60)
        eligibilityDateMenuItem.title = "Offer starts on: \(Self.dateFormatter.string(from: eligibilityDate))"

        if let presentationDate = winbackOfferStore.getOfferPresentationDate() {
            let offerEndDate = presentationDate.addingTimeInterval(5 * 24 * 60 * 60)
            let urgencyMessageDate = offerEndDate.addingTimeInterval(-2 * 24 * 60 * 60)

            offerStartDateMenuItem.title = "Offer Window Start: \(Self.dateFormatter.string(from: presentationDate))"
            offerEndDateMenuItem.title = "Offer Window Ends: \(Self.dateFormatter.string(from: offerEndDate))"
            modalPresentationDateMenuItem.title = "Launch Prompt Shown: \(Self.dateFormatter.string(from: presentationDate))"
            urgencyMessageDateMenuItem.title = "Urgency message starts: \(Self.dateFormatter.string(from: urgencyMessageDate))"
        } else {
            offerStartDateMenuItem.title = "Offer Window Start: Not started"
            offerEndDateMenuItem.title = "Offer Window Ends: N/A"
            modalPresentationDateMenuItem.title = "Launch Prompt Shown: No"
            urgencyMessageDateMenuItem.title = "Urgency Message: N/A"
        }

        let hasRedeemed = winbackOfferStore.hasRedeemedOffer()
        let presentationDate = winbackOfferStore.getOfferPresentationDate()
        storageStateMenuItem.title = "Storage: Redeemed=\(hasRedeemed), LaunchPromptPresented=\(presentationDate != nil)"
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

      enum Key: String {
          case simulatedTodayDate = "debug.winback-offer.simulated-today-date"
      }

      private let keyValueStore: ThrowingKeyValueStoring

      init(keyValueStore: ThrowingKeyValueStoring) {
          self.keyValueStore = keyValueStore
      }

      var simulatedTodayDate: Date {
          get {
              guard let timestamp = try? keyValueStore.object(forKey: Key.simulatedTodayDate.rawValue) as? TimeInterval else {
                  return Date()
              }
              return Date(timeIntervalSince1970: timestamp)
          }
          set {
              try? keyValueStore.set(newValue.timeIntervalSince1970, forKey: Key.simulatedTodayDate.rawValue)
          }
      }

      func reset() {
          try? keyValueStore.removeObject(forKey: Key.simulatedTodayDate.rawValue)
      }
  }
