//
//  FreemiumDBPUserStateManaging.swift
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

/// The outcome of a freemium user's first scan. Stored as a raw string in UserDefaults.
public enum FreemiumFirstScanResult: String, Codable {
    case noMatches
    case matchesFound
}

/// Persists freemium user state across sessions. Callers use the `record…IfNeeded`
/// methods for writes; auth gating, first-write guards, and write serialization are
/// the implementation's responsibility.
public protocol FreemiumDBPUserStateManaging {
    /// Whether the user has activated the freemium DBP feature (saved a profile and started scanning).
    var didActivate: Bool { get }

    /// Timestamp of the first time the user saved their profile via the freemium flow.
    var firstProfileSavedTimestamp: Date? { get }

    /// Result of the first freemium scan (not the most recent).
    var firstScanResult: FreemiumFirstScanResult? { get }

    /// Timestamp of the moment the user upgraded from freemium to a paid subscription.
    var upgradeToSubscriptionTimestamp: Date? { get }

    /// Records a successful profile save for unauthenticated users. First-write on timestamp.
    func recordProfileSavedIfNeeded() async

    /// Records the first freemium scan's result. First-scan-wins: later scans are ignored.
    func recordFirstScanResultIfNeeded(hasMatches: Bool) async

    /// Records the moment the user upgrades to a paid subscription. Must only be called
    /// on a real purchase/upgrade signal — not from a generic "current state is subscribed"
    /// listener. See spec §3.
    func recordSubscriptionUpgradeIfEligible() async

    /// Clears every stored value. For debug tools.
    func resetAllState()
}
