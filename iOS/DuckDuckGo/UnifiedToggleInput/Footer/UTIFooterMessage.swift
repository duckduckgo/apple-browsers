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

import Foundation

enum UTIFooterAction: Equatable {
    case reduceUsage
    case switchModel
}

struct UTIFooterMessage: Equatable {

    enum Icon: Equatable {
        case usageRing(progress: Double)
        case alert
    }

    struct PrimaryAction: Equatable {
        let title: String
        let action: UTIFooterAction
    }

    let icon: Icon
    let title: String
    let subtitle: String?
    let primaryAction: PrimaryAction?
    let isDismissible: Bool
}

struct UTIFooterResetDescriber {

    private let formatter: DateComponentsFormatter

    init(locale: Locale = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        self.formatter = formatter
    }

    func describe(until resetsAt: Date, from now: Date) -> String {
        let remaining = max(resetsAt.timeIntervalSince(now), Constants.minimumRemaining)
        return formatter.string(from: remaining) ?? ""
    }

    private enum Constants {
        static let minimumRemaining: TimeInterval = 60
    }
}
