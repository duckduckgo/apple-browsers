//
//  DuckAiUsageSnapshot.swift
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

/// Web names both the key and the value, so native writes them verbatim.
public struct DuckAiNativeStorageEntry: Equatable {

    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Decided web-side: native maps `id` to copy rather than re-deriving the message from percentages,
/// tier or model rank, which is how the two ended up disagreeing.
public struct DuckAiUsageNotice: Equatable {

    /// Unknown ids are dropped: a message web adds later should show nothing rather than the wrong copy.
    public enum ID: String {
        case approaching
        case freeReached
        case dailyReached
        case weeklyReachedDegraded
        case weeklyReached
    }

    public let id: ID
    public let window: DuckAiUsageWindow
    /// Already capped web-side (99 until reached), so native shows it as sent.
    public let percentUsed: Int
    public let resetsAt: Date
    public let reached: Bool
    public let dismissible: Bool

    public init(id: ID, window: DuckAiUsageWindow, percentUsed: Int, resetsAt: Date, reached: Bool, dismissible: Bool) {
        self.id = id
        self.window = window
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
        self.reached = reached
        self.dismissible = dismissible
    }
}

public struct DuckAiUsageCta: Equatable {

    public enum ID: String {
        case bypassWeekly
        case switchToCheaper
        case switchToFree
        case subscribe

        var asksForModelSwitch: Bool {
            switch self {
            case .switchToCheaper, .switchToFree: return true
            case .bypassWeekly, .subscribe: return false
            }
        }
    }

    /// `modelIds` never includes the id it is keyed against.
    public struct Target: Equatable {
        public let modelId: String?
        public let modelIds: [String]

        public static let none = Target(modelId: nil, modelIds: [])

        public var isEmpty: Bool { modelId == nil && modelIds.isEmpty }

        public var candidateModelIds: [String] {
            var seen = Set<String>()
            return ([modelId].compactMap { $0 } + modelIds).filter { seen.insert($0).inserted }
        }

        public init(modelId: String?, modelIds: [String]) {
            self.modelId = modelId
            self.modelIds = modelIds
        }
    }

    public let id: ID
    public let target: Target
    /// For when the native picker is on a different model than web is.
    public let byModelId: [String: Target]
    /// `bypassWeekly` only: web owns the key and the value, so they are written verbatim.
    public let putEntries: [DuckAiNativeStorageEntry]

    public init(id: ID,
                target: Target = .none,
                byModelId: [String: Target] = [:],
                putEntries: [DuckAiNativeStorageEntry] = []) {
        self.id = id
        self.target = target
        self.byModelId = byModelId
        self.putEntries = putEntries
    }

    /// A retarget table with no top-level target is web saying it is already on the cheapest model,
    /// while other picker models still have somewhere to go.
    public func target(forSelectedModelId modelId: String?) -> Target {
        guard let modelId, let retarget = byModelId[modelId] else { return target }
        return retarget
    }
}

/// The `daily` / `weekly` windows web still writes are deliberately not read: they are for older
/// clients, and a missing window means "no data", not 0%.
public struct DuckAiUsageSnapshot: Equatable {

    public let notice: DuckAiUsageNotice?
    public let cta: DuckAiUsageCta?
    /// So "has web published a new snapshot since the user acted on this one?" is answerable.
    public let signature: String?

    public static let noData = DuckAiUsageSnapshot(notice: nil, cta: nil, signature: nil)

    public var hasNotice: Bool { notice != nil }

    public init(notice: DuckAiUsageNotice?, cta: DuckAiUsageCta?, signature: String? = nil) {
        self.notice = notice
        self.cta = cta
        self.signature = signature
    }

    /// Anything unexpected degrades to no-data, and a notice past its reset is dropped — it would
    /// warn on after the limit lifted.
    public static func make(entryValue: Any?, now: Date) -> DuckAiUsageSnapshot {
        guard let root = rootObject(from: entryValue) else { return .noData }

        // A CTA has nothing to hang off without a notice.
        guard let notice = notice(from: root["notice"], now: now) else {
            return DuckAiUsageSnapshot(notice: nil, cta: nil, signature: signature(for: entryValue))
        }
        return DuckAiUsageSnapshot(notice: notice,
                                   cta: cta(from: root["cta"]),
                                   signature: signature(for: entryValue))
    }

    // MARK: - Notice

    private static func notice(from value: Any?, now: Date) -> DuckAiUsageNotice? {
        guard let object = value as? [String: Any],
              let id = (object["id"] as? String).flatMap(DuckAiUsageNotice.ID.init(rawValue:)),
              let window = (object["window"] as? String).flatMap(DuckAiUsageWindow.init(rawValue:)),
              let resetsAt = date(from: object["resetsAt"]),
              resetsAt > now else { return nil }

        // The ids already say whether this is a hard limit, so absent flags fall back to them.
        let reached = bool(from: object["reached"]) ?? (id != .approaching)
        let percentUsed = percent(from: object["percentUsed"])
        // Otherwise an approaching message reads "0% of daily limit".
        guard let percentUsed = percentUsed ?? (reached ? 100 : nil) else { return nil }

        return DuckAiUsageNotice(id: id,
                                 window: window,
                                 percentUsed: percentUsed,
                                 resetsAt: resetsAt,
                                 reached: reached,
                                 dismissible: bool(from: object["dismissible"]) ?? !reached)
    }

    // MARK: - CTA

    private static func cta(from value: Any?) -> DuckAiUsageCta? {
        guard let object = value as? [String: Any],
              let id = (object["id"] as? String).flatMap(DuckAiUsageCta.ID.init(rawValue:)) else { return nil }

        let byModelId = (object["byModelId"] as? [String: Any])?.compactMapValues(target(from:)) ?? [:]
        return DuckAiUsageCta(id: id,
                              target: target(from: object) ?? .none,
                              byModelId: byModelId,
                              putEntries: entries(from: object["putEntries"]))
    }

    private static func target(from value: Any?) -> DuckAiUsageCta.Target? {
        guard let object = value as? [String: Any] else { return nil }
        let modelIds = (object["modelIds"] as? [Any])?.compactMap { $0 as? String } ?? []
        return DuckAiUsageCta.Target(modelId: object["modelId"] as? String, modelIds: modelIds)
    }

    /// A non-string pair is dropped rather than coerced: these go straight into the blob web parses.
    private static func entries(from value: Any?) -> [DuckAiNativeStorageEntry] {
        switch value {
        case let items as [Any]:
            return items.compactMap { item in
                guard let object = item as? [String: Any],
                      let key = object["key"] as? String,
                      let value = object["value"] as? String,
                      !key.isEmpty else { return nil }
                return DuckAiNativeStorageEntry(key: key, value: value)
            }
        case let object as [String: Any]:
            return object.compactMap { key, value in
                guard let value = value as? String, !key.isEmpty else { return nil }
                return DuckAiNativeStorageEntry(key: key, value: value)
            }
            // So the same payload always produces the same write order.
            .sorted { $0.key < $1.key }
        default:
            return []
        }
    }

    // MARK: - Primitives

    /// The entries namespace mirrors web's `localStorage`, so the value is a JSON-encoded string;
    /// a dictionary is accepted in case a future writer stores the object directly.
    private static func rootObject(from value: Any?) -> [String: Any]? {
        switch value {
        case let json as String:
            guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = json.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        case let object as [String: Any]:
            return object
        default:
            return nil
        }
    }

    /// The string as written, so two reads of the same snapshot compare equal.
    private static func signature(for value: Any?) -> String? {
        switch value {
        case let json as String:
            return json
        case let object as [String: Any]:
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }

    /// The `CFBoolean` check rejects `true`/`false`, which would otherwise bridge to `1`/`0`.
    private static func percent(from value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite else { return nil }
        return Int(min(max(percent, 0), 100).rounded())
    }

    /// A `1` here more likely means a payload we don't understand.
    private static func bool(from value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// `Date.toISOString()` always carries fractional seconds; the fallback covers hand-seeded timestamps.
    private static func date(from value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
