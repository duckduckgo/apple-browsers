//
//  TabTerminationTelemetry.swift
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

import FeatureFlags_iOS
import Persistence
import PixelKit
import PrivacyConfig
import UIKit

typealias PixelKitFiring = PixelFiring

@MainActor
protocol TabTerminationTelemetry {
    func webContentProcessDidTerminate(activeTabCount: Int)
    func didReceiveMemoryWarning(activeTabCount: Int)
}

struct TabEvictionSettings {

    private enum Constants {
        static let defaultMemoryWarningTelemetryWindow: TimeInterval = 60
        static let defaultPhoneCapacity = 20
        static let defaultPadCapacity = 10
        static let memoryWarningTelemetryWindowKey = "memoryWarningTelemetryWindowSeconds"
        static let phoneCapacityKey = "maxCapacityPhone"
        static let padCapacityKey = "maxCapacityPad"
    }

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    var memoryWarningTelemetryWindow: TimeInterval {
        positiveNumber(forKey: Constants.memoryWarningTelemetryWindowKey,
                       subfeature: .tabEvictionOnMemoryWarning) ?? Constants.defaultMemoryWarningTelemetryWindow
    }

    func maximumCapacity(isPad: Bool) -> Int {
        let key = isPad ? Constants.padCapacityKey : Constants.phoneCapacityKey
        let defaultValue = isPad ? Constants.defaultPadCapacity : Constants.defaultPhoneCapacity
        guard let value = positiveNumber(forKey: key, subfeature: .tabLRUEviction),
              value.rounded(.towardZero) == value,
              value < Double(Int.max) else {
            return defaultValue
        }
        return Int(value)
    }

    private func positiveNumber(forKey key: String, subfeature: iOSBrowserConfigSubfeature) -> Double? {
        guard let json = privacyConfigurationManager.privacyConfig.settings(for: subfeature),
              let data = json.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dictionary[key],
              !(value is Bool),
              let number = value as? NSNumber,
              number.doubleValue.isFinite,
              number.doubleValue > 0 else {
            return nil
        }
        return number.doubleValue
    }
}

@MainActor
final class DefaultTabTerminationTelemetry: TabTerminationTelemetry {

    private let featureFlagger: FeatureFlagger
    private let occurrenceStore: TabTerminationTelemetryOccurrenceStore
    private let pixelFiring: (any PixelKitFiring)?
    private let applicationState: @MainActor () -> UIApplication.State
    private let memoryFootprint: @MainActor () -> UInt64?
    private let date: () -> Date
    private let memoryWarningTelemetryWindow: () -> TimeInterval
    private var lastMemoryWarningDate: Date?
    private var memoryWarningDates = [Date]()

    init(featureFlagger: FeatureFlagger,
         keyValueStore: KeyValueStoring,
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared,
         applicationState: (@MainActor () -> UIApplication.State)? = nil,
         memoryFootprint: (@MainActor () -> UInt64?)? = nil,
         memoryWarningTelemetryWindow: @escaping () -> TimeInterval = { 60 },
         date: @escaping () -> Date = Date.init) {
        self.featureFlagger = featureFlagger
        self.occurrenceStore = TabTerminationTelemetryOccurrenceStore(keyValueStore: keyValueStore)
        self.pixelFiring = pixelFiring
        self.applicationState = applicationState ?? { UIApplication.shared.applicationState }
        self.memoryFootprint = memoryFootprint ?? { Self.currentMemoryFootprint() }
        self.memoryWarningTelemetryWindow = memoryWarningTelemetryWindow
        self.date = date
    }

    func webContentProcessDidTerminate(activeTabCount: Int) {
        guard featureFlagger.isFeatureOn(.tabTerminationTelemetry) else { return }

        let terminationDate = date()
        let appStatePixel: TabTerminationTelemetryPixel = applicationState() == .background ? .background : .foreground
        pixelFiring?.fire(appStatePixel, frequency: .dailyAndCount)

        let occurrence = occurrenceStore.nextOccurrence(on: terminationDate)
        let occurrencePixel = TabTerminationTelemetryPixel.occurrence(.init(occurrence))
        pixelFiring?.fire(occurrencePixel, frequency: .daily)

        if let memoryFootprint = memoryFootprint() {
            let memoryPixel = TabTerminationTelemetryPixel.memory(.init(bytes: memoryFootprint))
            pixelFiring?.fire(memoryPixel, frequency: .dailyAndCount)
        }

        let activeTabsPixel = TabTerminationTelemetryPixel.activeTabs(.init(activeTabCount))
        pixelFiring?.fire(activeTabsPixel, frequency: .dailyAndCount)

        if let lastMemoryWarningDate {
            let timeSinceWarning = max(terminationDate.timeIntervalSince(lastMemoryWarningDate), 0)
            let timePixel = TabTerminationTelemetryPixel.timeSinceMemoryWarning(.init(number: timeSinceWarning))
            pixelFiring?.fire(timePixel, frequency: .standard)
        }
    }

    func didReceiveMemoryWarning(activeTabCount: Int) {
        guard featureFlagger.isFeatureOn(.tabTerminationTelemetry) else { return }
        let warningDate = date()
        lastMemoryWarningDate = warningDate
        memoryWarningDates.removeAll {
            $0 > warningDate || warningDate.timeIntervalSince($0) > memoryWarningTelemetryWindow()
        }
        memoryWarningDates.append(warningDate)

        pixelFiring?.fire(TabTerminationTelemetryPixel.memoryWarningActiveTabs(.init(activeTabCount)), frequency: .dailyAndCount)
        pixelFiring?.fire(TabTerminationTelemetryPixel.memoryWarningOccurrence(.init(memoryWarningDates.count)), frequency: .standard)
    }

    nonisolated static func currentMemoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }
}

final class TabTerminationTelemetryOccurrenceStore {

    private enum Key: String {
        case date = "tab-termination-telemetry.occurrence-date"
        case count = "tab-termination-telemetry.occurrence-count"
    }

    private let keyValueStore: KeyValueStoring
    private let calendar: Calendar

    init(keyValueStore: KeyValueStoring, calendar: Calendar = .current) {
        self.keyValueStore = keyValueStore
        self.calendar = calendar
    }

    func nextOccurrence(on date: Date) -> Int {
        let startOfDay = calendar.startOfDay(for: date)
        let storedDate = keyValueStore.object(forKey: Key.date.rawValue) as? Date
        let storedCount = keyValueStore.object(forKey: Key.count.rawValue) as? Int ?? 0
        let nextCount = storedDate == startOfDay ? storedCount + 1 : 1

        keyValueStore.set(startOfDay, forKey: Key.date.rawValue)
        keyValueStore.set(nextCount, forKey: Key.count.rawValue)
        return nextCount
    }
}

enum TabTerminationTelemetryPixel: PixelKitEvent, PixelKitEventWithCustomPrefix {
    case interactionStateFailedToRestore
    case interactionStateFailedToRestoreDaily
    case foreground
    case background
    case occurrence(OccurrenceBucket)
    case memory(MemoryBucket)
    case activeTabs(ActiveTabBucket)
    case timeSinceMemoryWarning(TimeBucket)
    case memoryWarningActiveTabs(ActiveTabBucket)
    case memoryWarningOccurrence(OccurrenceBucket)

    var name: String {
        switch self {
        case .interactionStateFailedToRestore:
            return "m_d_tab-interaction-state_failed-to-restore"
        case .interactionStateFailedToRestoreDaily:
            return "m_d_tab-interaction-state_failed-to-restore_daily"
        case .foreground:
            return "debug_webkit_termination_foreground"
        case .background:
            return "debug_webkit_termination_background"
        case .occurrence(let bucket):
            return "debug_webkit_termination_occurrence_\(bucket.rawValue)"
        case .memory(let bucket):
            return "debug_webkit_termination_memory_\(bucket.rawValue)"
        case .activeTabs(let bucket):
            return "debug_webkit_termination_active-tabs_\(bucket.rawValue)"
        case .timeSinceMemoryWarning(let bucket):
            return "debug_webkit_termination_time-since-memory-warning_\(bucket.rawValue)"
        case .memoryWarningActiveTabs(let bucket):
            return "debug_memory_warning_active-tabs_\(bucket.rawValue)"
        case .memoryWarningOccurrence(let bucket):
            return "debug_memory_warning_occurrence-in-window_\(bucket.rawValue)"
        }
    }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var namePrefix: String { "" }

    enum OccurrenceBucket: String {
        case one = "1"
        case two = "2"
        case three = "3"
        case four = "4"
        case fiveOrMore = "5-plus"

        init(_ count: Int) {
            switch count {
            case 1:
                self = .one
            case 2:
                self = .two
            case 3:
                self = .three
            case 4:
                self = .four
            default:
                self = .fiveOrMore
            }
        }
    }

    enum MemoryBucket: String {
        case lessThan512 = "less-512"
        case from512To1023 = "512-1023"
        case from1024To2047 = "1024-2047"
        case from2048To4095 = "2048-4095"
        case from4096To8191 = "4096-8191"
        case from8192To16383 = "8192-16383"
        case from16384 = "16384-plus"

        init(bytes: UInt64) {
            switch bytes / 1_048_576 {
            case ..<512:
                self = .lessThan512
            case 512..<1024:
                self = .from512To1023
            case 1024..<2048:
                self = .from1024To2047
            case 2048..<4096:
                self = .from2048To4095
            case 4096..<8192:
                self = .from4096To8191
            case 8192..<16384:
                self = .from8192To16383
            default:
                self = .from16384
            }
        }
    }

    enum ActiveTabBucket: String {
        case one = "1"
        case from2To5 = "2-5"
        case from6To10 = "6-10"
        case from11To20 = "11-20"
        case from21To40 = "21-40"
        case from41To60 = "41-60"
        case from61To80 = "61-80"
        case from81 = "81-plus"

        init(_ count: Int) {
            switch count {
            case ...1:
                self = .one
            case 2...5:
                self = .from2To5
            case 6...10:
                self = .from6To10
            case 11...20:
                self = .from11To20
            case 21...40:
                self = .from21To40
            case 41...60:
                self = .from41To60
            case 61...80:
                self = .from61To80
            default:
                self = .from81
            }
        }
    }

    enum TimeBucket: String {
        case zero = "0"
        case lessThan01 = "0.1"
        case lessThan05 = "0.5"
        case lessThan1 = "1"
        case lessThan5 = "5"
        case lessThan10 = "10"
        case lessThan20 = "20"
        case lessThan40 = "40"
        case more

        init(number: Double) {
            switch number {
            case 0:
                self = .zero
            case ...0.1:
                self = .lessThan01
            case ...0.5:
                self = .lessThan05
            case ...1:
                self = .lessThan1
            case ...5:
                self = .lessThan5
            case ...10:
                self = .lessThan10
            case ...20:
                self = .lessThan20
            case ...40:
                self = .lessThan40
            default:
                self = .more
            }
        }
    }
}
