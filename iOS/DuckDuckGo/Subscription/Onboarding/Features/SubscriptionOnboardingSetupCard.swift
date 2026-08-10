//
//  SubscriptionOnboardingSetupCard.swift
//  DuckDuckGo
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

import SwiftUI
import DesignResourcesKit
import DuckUI
import UIComponents
import Persistence

struct SubscriptionOnboardingSetupCard: View {
    private enum Metrics {
        static let iconSpacing: CGFloat = 12
        static let titleTextSpacing: CGFloat = 4
        static let buttonTopSpacing: CGFloat = 16
    }

    private let visual: Graphic
    private let keyValueStore: ThrowingKeyValueStoring
    /// PIR is gated outside this card; a customer who cannot reach it is measured over four items, not five.
    private let isPIRAvailable: Bool
    private let isPIRActivated: Bool
    private let onContinue: () -> Void

    @State private var percentage = 0
    @State private var isShowing = false

    init(visual: Graphic,
         keyValueStore: ThrowingKeyValueStoring,
         isPIRAvailable: Bool,
         isPIRActivated: Bool,
         onContinue: @escaping () -> Void) {
        self.visual = visual
        self.keyValueStore = keyValueStore
        self.isPIRAvailable = isPIRAvailable
        self.isPIRActivated = isPIRActivated
        self.onContinue = onContinue
    }

    var body: some View {
        // Always mounted, rendering nothing while hidden. A card taken out of the hierarchy has no `onAppear`,
        // so it could never re-read the store and bring itself back.
        Group {
            if isShowing {
                card
            }
        }
        .onAppear(perform: refresh)
    }

    private var card: some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .leading, visual: visual, size: .size40, spacing: Metrics.iconSpacing),
                title: CardItemText(title, font: .headline),
                text: CardItemText(UserText.subscriptionOnboardingSetupCardBody, font: .bodyRegular),
                titleTextSpacing: Metrics.titleTextSpacing),
            style: .borderless) {
                Button(UserText.subscriptionOnboardingSetupCardButton, action: onContinue)
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .padding(.top, Metrics.buttonTopSpacing)
            }
    }

    private var title: String {
        String(format: UserText.subscriptionOnboardingSetupCardTitleFormat, percentage)
    }

    /// Reads progress and decides whether to show, on every appearance — the checklist advances outside this
    /// screen. PIR completes inside Data Broker Protection, so it is composed in at read time rather than
    /// recorded here.
    private func refresh() {
        var store = SubscriptionOnboardingProgressStore(keyValueStore: keyValueStore)
        let completed = isPIRActivated ? store.completedItems.union([.pir]) : store.completedItems
        percentage = SubscriptionOnboardingChecklistItem.completionPercentage(
            completed: completed,
            checklist: SubscriptionOnboardingChecklistItem.checklist(isPIRAvailable: isPIRAvailable))
        isShowing = store.shouldShowSetupCard(percentage: percentage, now: Date())
    }
}

#if DEBUG

/// The shared in-memory store lives in a test-only module, so previews bring their own.
private final class PreviewKeyValueStore: ThrowingKeyValueStoring {
    private var values: [String: Any] = [:]
    func object(forKey defaultName: String) throws -> Any? { values[defaultName] }
    func set(_ value: Any?, forKey defaultName: String) throws { values[defaultName] = value }
    func removeObject(forKey defaultName: String) throws { values.removeValue(forKey: defaultName) }
}

private struct SubscriptionOnboardingSetupCardPreview: View {
    var body: some View {
        ScrollView {
            // PIR unavailable, so the checklist is four items and these read 3/4 and 1/4.
            VStack(spacing: 24) {
                card(completed: [.vpn, .widget, .idtr])
                card(completed: [.vpn])
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }

    private func card(completed: Set<SubscriptionOnboardingChecklistItem>) -> some View {
        let keyValueStore = PreviewKeyValueStore()
        var store = SubscriptionOnboardingProgressStore(keyValueStore: keyValueStore)
        store.completedItems = completed

        return SubscriptionOnboardingSetupCard(visual: .image(Image(.subscription56)),
                                               keyValueStore: keyValueStore,
                                               isPIRAvailable: false,
                                               isPIRActivated: false,
                                               onContinue: {})
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingSetupCardPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingSetupCardPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingSetupCardPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
