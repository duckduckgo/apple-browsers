//
//  UTIFooterMessage.swift
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

import AIChat
import Foundation

struct CreateImageModelSwitchNotice: Equatable {
    let previousModelShortName: String
    let newModelShortName: String
    let previousModelHasExtraPrivacyProtections: Bool

    init(previousModel: AIChatModel, newModel: AIChatModel) {
        previousModelShortName = previousModel.shortName
        newModelShortName = newModel.shortName
        previousModelHasExtraPrivacyProtections = previousModel.provider == .oss
    }
}

struct UTIFooterMessage: Equatable {

    enum Icon: Equatable {
        case none
        case usageRing(progress: Double, severity: DuckAiUsageSeverity)
        case alert
        case info
        case modelSwitch
    }

    struct PrimaryAction: Equatable {
        let title: String
    }

    let icon: Icon
    let title: String
    let subtitle: String?
    let primaryAction: PrimaryAction?
    let isDismissible: Bool
}

/// Localizes the interval the shared resolver already bucketed, so "Resets in" reads as
/// "2 days" rather than the module's unlocalized "2d".
struct UTIFooterResetDescriber {

    private let formatter: DateComponentsFormatter

    init(locale: Locale = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour]
        formatter.maximumUnitCount = 1
        self.formatter = formatter
    }

    /// Whole days or whole hours only: the interval arrives already rounded up, and web never
    /// counts a reset down in minutes.
    func describe(_ interval: DuckAiUsageResetInterval) -> String {
        switch interval {
        case .days(let days):
            return formatter.string(from: TimeInterval(max(1, days)) * Constants.secondsPerDay) ?? ""
        case .hours(let hours):
            return formatter.string(from: TimeInterval(max(1, hours)) * Constants.secondsPerHour) ?? ""
        }
    }

    private enum Constants {
        static let secondsPerHour: TimeInterval = 60 * 60
        static let secondsPerDay: TimeInterval = 24 * 60 * 60
    }
}
