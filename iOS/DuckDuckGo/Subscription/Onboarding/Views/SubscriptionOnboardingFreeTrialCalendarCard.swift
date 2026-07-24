//
//  SubscriptionOnboardingFreeTrialCalendarCard.swift
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
import UIComponents

/// Precomputes what `SubscriptionOnboardingFreeTrialCalendarCard` renders — the current trial day, the
/// calendar strip's day-of-month labels, the marker position, and the billing line — deriving them at
/// `init` from the `freeTrialStartDate` / `billingStartDate` inputs, which aren't themselves stored. The
/// strip is anchored at `freeTrialStartDate` and spans `trialLength` days, so the marker advances to
/// "today" as the trial progresses. `now` and `calendar` are injectable for deterministic tests/previews.
struct SubscriptionOnboardingFreeTrialCalendarCardModel {
    let trialLength: Int

    /// The 1-based day of the trial that today falls on, clamped to `1...trialLength`.
    let currentTrialDay: Int

    /// `currentTrialDay` rendered in the calendar's locale, so its numerals match the localized billing date.
    let currentTrialDayText: String

    /// Zero-based index of the marker within the strip.
    let markerIndex: Int

    /// Day-of-month numbers for each day of the trial window, anchored at the start date.
    let dayLabels: [String]

    /// The billing line, e.g. "Billing starts on May 7, 2026", formatted from `billingStartDate` using the
    /// injected calendar's time zone and locale.
    let billingText: String

    init(freeTrialStartDate: Date,
         billingStartDate: Date,
         trialLength: Int = 7,
         now: Date = Date(),
         calendar: Calendar = .current) {
        let trialLength = max(1, trialLength)
        self.trialLength = trialLength

        let start = calendar.startOfDay(for: freeTrialStartDate)
        let today = calendar.startOfDay(for: now)
        let elapsedDays = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let currentTrialDay = min(max(elapsedDays + 1, 1), trialLength)
        self.currentTrialDay = currentTrialDay
        self.markerIndex = currentTrialDay - 1

        let locale = calendar.locale ?? .current
        func localizedNumeral(_ value: Int) -> String {
            value.formatted(.number.grouping(.never).locale(locale))
        }
        self.currentTrialDayText = localizedNumeral(currentTrialDay)
        self.dayLabels = (0..<trialLength).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: start) ?? start
            return localizedNumeral(calendar.component(.day, from: date))
        }

        let dateStyle = Date.FormatStyle(date: .abbreviated, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        self.billingText = String(format: UserText.subscriptionOnboardingFreeTrialBillingFormat,
                                  billingStartDate.formatted(dateStyle))
    }
}

/// The "Day N of your free trial" card: a centered heading emphasising the current trial day, a billing
/// line, and a calendar strip (day-of-month labels over a capsule bar filled up to today's marker). Values
/// come from `SubscriptionOnboardingFreeTrialCalendarCardModel`. Built on `UIComponents.BubbleView` for its
/// translucent fill.
struct SubscriptionOnboardingFreeTrialCalendarCard: View {
    private let model: SubscriptionOnboardingFreeTrialCalendarCardModel

    private enum Metrics {
        static let cornerRadius: CGFloat = 26
        static let contentPadding: CGFloat = 24
        static let contentSpacing: CGFloat = 16
        static let titleSubtitleSpacing: CGFloat = 2
        static let stripWidth: CGFloat = 306
        static let stripHeight: CGFloat = 20
        static let stripBorderWidth: CGFloat = 1
        static let stripSpacing: CGFloat = 8
        static let markerSize: CGFloat = 32
    }

    init(model: SubscriptionOnboardingFreeTrialCalendarCardModel) {
        self.model = model
    }

    var body: some View {
        let billingText = model.billingText
        let accessibilityText = UserText.subscriptionOnboardingFreeTrialTitlePrefix
            + model.currentTrialDayText
            + UserText.subscriptionOnboardingFreeTrialTitleSuffix
            + ". "
            + billingText
        return BubbleView(
            arrowLength: 0,
            arrowWidth: 0,
            cornerRadius: Metrics.cornerRadius,
            fillColor: Color(designSystemColor: .accentAltGlowPrimary),
            borderColor: .clear,
            borderWidth: 0,
            contentPadding: EdgeInsets(top: Metrics.contentPadding,
                                       leading: Metrics.contentPadding,
                                       bottom: Metrics.contentPadding,
                                       trailing: Metrics.contentPadding)
        ) {
            VStack(spacing: Metrics.contentSpacing) {
                VStack(spacing: Metrics.titleSubtitleSpacing) {
                    heading

                    Text(verbatim: billingText)
                        .font(Font(UIFont.daxSubheadRegular()))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }

                calendarStrip
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(verbatim: UserText.subscriptionOnboardingFreeTrialTitlePrefix)
                .font(Font(UIFont.daxHeadline()))
            Text(verbatim: model.currentTrialDayText)
                .font(Font(UIFont.daxTitle1()).monospacedDigit())
            Text(verbatim: UserText.subscriptionOnboardingFreeTrialTitleSuffix)
                .font(Font(UIFont.daxHeadline()))
        }
        .foregroundColor(Color(designSystemColor: .textPrimary))
    }

    private var calendarStrip: some View {
        let labels = model.dayLabels
        let columnWidth = Metrics.stripWidth / CGFloat(max(labels.count, 1))
        let markerCenterX = columnWidth * (CGFloat(clampedMarkerIndex(labels)) + 0.5)

        return VStack(spacing: Metrics.stripSpacing) {
            HStack(spacing: 0) {
                ForEach(labels.indices, id: \.self) { index in
                    Text(verbatim: labels[index])
                        .font(Font(UIFont.daxFootnoteSemibold()))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .frame(width: columnWidth)
                }
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(singleUseColor: .rebranding(.calendarStripYellow)))
                    .frame(width: Metrics.stripWidth, height: Metrics.stripHeight)

                Capsule()
                    .fill(Color(designSystemColor: .alertYellow))
                    .frame(width: max(markerCenterX, Metrics.stripHeight), height: Metrics.stripHeight)

                Capsule()
                    .strokeBorder(Color(designSystemColor: .containerBorderPrimary), lineWidth: Metrics.stripBorderWidth)
                    .frame(width: Metrics.stripWidth, height: Metrics.stripHeight)

                marker
                    .offset(x: markerCenterX - Metrics.markerSize / 2)
            }
            .frame(width: Metrics.stripWidth, height: Metrics.markerSize)
        }
        .frame(width: Metrics.stripWidth)
    }

    private var marker: some View {
        Image(.subscription56)
            .resizable()
            .frame(width: Metrics.markerSize, height: Metrics.markerSize)
    }

    private func clampedMarkerIndex(_ labels: [String]) -> Int {
        min(max(model.markerIndex, 0), max(labels.count - 1, 0))
    }
}

#if DEBUG

private extension SubscriptionOnboardingFreeTrialCalendarCardModel {
    /// Builds a deterministic preview model `dayOffset` days into a `length`-day trial that starts on the
    /// given day of May 2026, so previews render a stable "Day N" regardless of the current date.
    static func preview(startMonth: Int = 5, startDay: Int, dayOffset: Int, length: Int = 7) -> SubscriptionOnboardingFreeTrialCalendarCardModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        let start = calendar.date(from: DateComponents(year: 2026, month: startMonth, day: startDay)) ?? Date()
        let now = calendar.date(byAdding: .day, value: dayOffset, to: start) ?? start
        let billing = calendar.date(byAdding: .day, value: length, to: start) ?? start
        return SubscriptionOnboardingFreeTrialCalendarCardModel(freeTrialStartDate: start,
                                          billingStartDate: billing,
                                          trialLength: length,
                                          now: now,
                                          calendar: calendar)
    }
}

private struct SubscriptionOnboardingFreeTrialCalendarCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Purchase date May 7 — first day.
                SubscriptionOnboardingFreeTrialCalendarCard(model: .preview(startDay: 7, dayOffset: 0))
                // Purchase date May 7 — midway through the trial.
                SubscriptionOnboardingFreeTrialCalendarCard(model: .preview(startDay: 7, dayOffset: 3))
                // Purchase date May 31 — the strip crosses the month boundary into June.
                SubscriptionOnboardingFreeTrialCalendarCard(model: .preview(startDay: 31, dayOffset: 2))
                // Purchase date May 7 — last day.
                SubscriptionOnboardingFreeTrialCalendarCard(model: .preview(startDay: 7, dayOffset: 6))
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingFreeTrialCalendarCardPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingFreeTrialCalendarCardPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingFreeTrialCalendarCardPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
