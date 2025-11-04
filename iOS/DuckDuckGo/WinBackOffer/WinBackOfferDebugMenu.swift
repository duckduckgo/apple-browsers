//
//  WinBackOfferDebugMenu.swift
//  DuckDuckGo
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

import SwiftUI
import Subscription
import Persistence
import Core

// MARK: - View Model

final class WinBackOfferDebugViewModel: ObservableObject {
    private var winbackOfferStore: WinbackOfferStoring
    let debugStore: WinBackOfferDebugStore

    @Published var simulatedToday: Date
    @Published var churnDate: Date?
    @Published var eligibilityDate: Date?
    @Published var offerStartDate: Date?
    @Published var offerEndDate: Date?
    @Published var urgencyMessageDate: Date?
    @Published var hasRedeemed: Bool = false
    @Published var launchPromptPresentationDate: Date?

    init(keyValueStore: ThrowingKeyValueStoring) {
        let store = WinbackOfferStore(keyValueStore: keyValueStore)
        self.winbackOfferStore = store
        self.debugStore = WinBackOfferDebugStore(keyValueStore: keyValueStore)
        self.simulatedToday = debugStore.simulatedTodayDate
        updateState()
    }

    /// Simulate churn by storing the current date as the churn date.
    func simulateChurn() {
        let effectiveDate = debugStore.simulatedTodayDate
        winbackOfferStore.storeChurnDate(effectiveDate)
        winbackOfferStore.setHasRedeemedOffer(false)
        winbackOfferStore.storeOfferPresentationDate(nil)
        winbackOfferStore.didDismissUrgencyMessage = false
        updateState()
    }

    /// Reset the Win-back offer by clearing the debug store and churn state.
    func resetWinBackOffer() {
        debugStore.reset()
        simulatedToday = debugStore.simulatedTodayDate
        winbackOfferStore.storeChurnDate(Date(timeIntervalSince1970: 0))
        winbackOfferStore.setHasRedeemedOffer(false)
        winbackOfferStore.storeOfferPresentationDate(nil)
        winbackOfferStore.didDismissUrgencyMessage = false
        updateState()
    }

    /// Jump to the first day of the Win-back offer (3 days after churn).
    func jumpToFirstDay() {
        if let existingChurnDate = winbackOfferStore.getChurnDate(),
           existingChurnDate.timeIntervalSince1970 > 0 {
            let firstDay = existingChurnDate.addingTimeInterval(.days(3))
            debugStore.simulatedTodayDate = firstDay
            simulatedToday = firstDay
            winbackOfferStore.storeOfferPresentationDate(nil)
        } else {
            let now = Date()
            let churnDate = now.addingTimeInterval(.days(-3)) // 3 days ago
            winbackOfferStore.storeChurnDate(churnDate)
            winbackOfferStore.setHasRedeemedOffer(false)
            winbackOfferStore.storeOfferPresentationDate(nil)
            winbackOfferStore.didDismissUrgencyMessage = false
            debugStore.simulatedTodayDate = now
            simulatedToday = now
        }
        updateState()
    }

    /// Jump to the last day of the Win-back offer (5 days after churn).
    func jumpToLastDay() {
        if let existingChurnDate = winbackOfferStore.getChurnDate(),
           existingChurnDate.timeIntervalSince1970 > 0 {
            let offerStart = existingChurnDate.addingTimeInterval(.days(3))
            if winbackOfferStore.getOfferPresentationDate() == nil {
                winbackOfferStore.storeOfferPresentationDate(offerStart)
            }
            if let presentationDate = winbackOfferStore.getOfferPresentationDate() {
                let lastDay = presentationDate.addingTimeInterval(.days(5)) // Last day of 5-day offer
                debugStore.simulatedTodayDate = lastDay
                simulatedToday = lastDay
            }
        } else {
            let now = Date()
            let churnDate = now.addingTimeInterval(.days(-8))
            winbackOfferStore.storeChurnDate(churnDate)
            winbackOfferStore.setHasRedeemedOffer(false)
            winbackOfferStore.storeOfferPresentationDate(now.addingTimeInterval(.days(-5)))
            winbackOfferStore.didDismissUrgencyMessage = false
            debugStore.simulatedTodayDate = now
            simulatedToday = now
        }
        updateState()
    }

    /// Override today's date by storing the given date in the debug store.
    func overrideTodaysDate(_ date: Date) {
        debugStore.simulatedTodayDate = date
        updateState()
    }

    private func updateState() {
        simulatedToday = debugStore.simulatedTodayDate

        guard let storedChurnDate = winbackOfferStore.getChurnDate(),
              storedChurnDate.timeIntervalSince1970 > 0 else {
            churnDate = nil
            eligibilityDate = nil
            offerStartDate = nil
            offerEndDate = nil
            urgencyMessageDate = nil
            hasRedeemed = false
            launchPromptPresentationDate = nil
            return
        }

        churnDate = storedChurnDate
        eligibilityDate = storedChurnDate.addingTimeInterval(.days(3)) // Eligible 3 days after churn

        if let presentationDate = winbackOfferStore.getOfferPresentationDate() {
            offerStartDate = presentationDate
            offerEndDate = presentationDate.addingTimeInterval(.days(5)) // 5 days availability after launch prompt is shown
            urgencyMessageDate = offerEndDate?.addingTimeInterval(.days(-1)) // Last day
            launchPromptPresentationDate = presentationDate
        } else {
            offerStartDate = nil
            offerEndDate = nil
            urgencyMessageDate = nil
            launchPromptPresentationDate = nil
        }

        hasRedeemed = winbackOfferStore.hasRedeemedOffer()
    }
}

// MARK: - View

/// Debug view for the Win-back offer.
/// 
/// Provides a UI to test the Win-back offer.
/// Supported actions:
/// - Simulate churn
/// - Override today's date
/// - Reset Win-back offer
/// - Jump to first day
/// - Jump to last day
/// - Current state
///
struct WinBackOfferDebugView: View {
    @StateObject private var viewModel: WinBackOfferDebugViewModel
    @State private var showingDatePicker: Bool = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = .current
        return formatter
    }()

    init(keyValueStore: ThrowingKeyValueStoring) {
        self._viewModel = StateObject(wrappedValue: WinBackOfferDebugViewModel(keyValueStore: keyValueStore))
    }

    var body: some View {
        List {
            Section(header: Text(verbatim: "Debug Controls")) {
                Button(action: {
                    viewModel.simulateChurn()
                }) {
                    Text(verbatim: "Simulate Churn")
                }

                Button(action: {
                    showingDatePicker = true
                }) {
                    Text(verbatim: "Override Today's Date")
                }

                Button(action: {
                    viewModel.resetWinBackOffer()
                }) {
                    Text(verbatim: "Reset Win-back Offer")
                }
            }

            Section(header: Text(verbatim: "Quick Test Scenarios")) {
                Button(action: {
                    viewModel.jumpToFirstDay()
                }) {
                    Text(verbatim: "Jump to First Day (3 days after churn)")
                }

                Button(action: {
                    viewModel.jumpToLastDay()
                }) {
                    Text(verbatim: "Jump to Last Day (offer ending)")
                }
            }

            Section(header: Text(verbatim: "Current State")) {
                LabeledRow(label: "Today's Date", value: Self.dateFormatter.string(from: viewModel.simulatedToday))

                if let churnDate = viewModel.churnDate {
                    LabeledRow(label: "Churn Date", value: Self.dateFormatter.string(from: churnDate))

                    if let eligibilityDate = viewModel.eligibilityDate {
                        LabeledRow(label: "Eligible Since", value: Self.dateFormatter.string(from: eligibilityDate))
                    }

                    if let presentationDate = viewModel.launchPromptPresentationDate {
                        LabeledRow(label: "Launch Prompt Shown", value: Self.dateFormatter.string(from: presentationDate))
                    } else {
                        LabeledRow(label: "Launch Prompt Shown", value: "No")
                    }

                    if let offerStartDate = viewModel.offerStartDate {
                        LabeledRow(label: "Offer Window Start", value: Self.dateFormatter.string(from: offerStartDate))
                    }

                    if let offerEndDate = viewModel.offerEndDate {
                        LabeledRow(label: "Offer Window Ends", value: Self.dateFormatter.string(from: offerEndDate))
                    }

                    if let urgencyMessageDate = viewModel.urgencyMessageDate {
                        LabeledRow(label: "Urgency Message", value: Self.dateFormatter.string(from: urgencyMessageDate))
                    }

                    LabeledRow(label: "Redeemed", value: viewModel.hasRedeemed ? "Yes" : "No")
                } else {
                    Text(verbatim: "No churn simulated")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: "Win-back Offer"))
        .sheet(isPresented: $showingDatePicker) {
            DatePickerView(date: $viewModel.simulatedToday) {
                viewModel.overrideTodaysDate(viewModel.simulatedToday)
            }
        }
    }
}

// MARK: - Supporting Views

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(verbatim: label)
            Spacer()
            Text(verbatim: value)
                .foregroundColor(.secondary)
        }
    }
}

private struct DatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    let onSave: () -> Void

    var body: some View {
        NavigationView {
            Form {
                DatePicker(
                    selection: $date,
                    displayedComponents: [.date]
                ) {
                    Text(verbatim: "Select Date")
                }
                .datePickerStyle(.graphical)
            }
            .navigationTitle(Text(verbatim: "Simulate Today's Date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text(verbatim: "Cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        onSave()
                        dismiss()
                    }) {
                        Text(verbatim: "Save")
                    }
                }
            }
        }
    }
}

// MARK: - Debug Store

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
