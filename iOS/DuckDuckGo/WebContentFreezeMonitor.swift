//
//  WebContentFreezeMonitor.swift
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

import Core
import FeatureFlags_iOS
import Persistence
import PixelKit
import PrivacyConfig
import UIKit

/// What the next launch needs to report a freeze the app exited in the middle of.
struct WebContentFreezeRecord {

    private enum Key: String {
        case start = "web-content-freeze.start-date"
        case background = "web-content-freeze.background-date"
        case attempts = "web-content-freeze.attempts"
        case context = "web-content-freeze.context"
    }

    private let store: KeyValueStoring

    init(store: KeyValueStoring = UserDefaults.app) {
        self.store = store
    }

    var startDate: Date? {
        get { store.object(forKey: Key.start.rawValue) as? Date }
        nonmutating set { store.set(newValue, forKey: Key.start.rawValue) }
    }

    /// When the app went to the background during the freeze, which is as far as the user saw it last.
    var backgroundDate: Date? {
        get { store.object(forKey: Key.background.rawValue) as? Date }
        nonmutating set { store.set(newValue, forKey: Key.background.rawValue) }
    }

    var attempts: Int {
        get { store.object(forKey: Key.attempts.rawValue) as? Int ?? 0 }
        nonmutating set { store.set(newValue, forKey: Key.attempts.rawValue) }
    }

    var context: WebContentHealthPixel.PageContext? {
        get { (store.object(forKey: Key.context.rawValue) as? Data).flatMap { try? JSONDecoder().decode(WebContentHealthPixel.PageContext.self, from: $0) } }
        nonmutating set { store.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.context.rawValue) }
    }

    func clear() {
        [Key.start, .background, .attempts, .context].forEach { store.removeObject(forKey: $0.rawValue) }
    }
}

/// Follows one tab's web content process freeze from WebKit's unresponsive callback to its end, and reports how long
/// it lasted and how often the user tried to get out. The owner ends the freeze as `closed` when the tab goes away.
@MainActor
final class WebContentFreezeMonitor: NSObject {

    enum Outcome: String {
        case recovered
        case closed
        /// The user pressed Fire while the page was frozen.
        case fire
        case terminated
        /// The app exited during the freeze; reported by the next launch.
        case appEnded = "app-ended"
    }

    enum DurationBucket: String {
        case upTo2 = "0-2"
        case upTo5 = "2-5"
        case upTo15 = "5-15"
        case upTo30 = "15-30"
        case upTo60 = "30-60"
        case more = "60-plus"
        case unknown

        init(seconds: TimeInterval) {
            switch seconds {
            case ..<2: self = .upTo2
            case ..<5: self = .upTo5
            case ..<15: self = .upTo15
            case ..<30: self = .upTo30
            case ..<60: self = .upTo60
            default: self = .more
            }
        }
    }

    enum AttemptsBucket: String {
        case zero = "0"
        case one = "1"
        case two = "2"
        case from3To5 = "3-5"
        case from6 = "6-plus"

        init(_ count: Int) {
            switch count {
            case ...0: self = .zero
            case 1: self = .one
            case 2: self = .two
            case 3...5: self = .from3To5
            default: self = .from6
            }
        }
    }

    private let pixelFiring: (any PixelKitFiring)?
    private let featureFlagger: FeatureFlagger
    // One record for every tab, so a second frozen tab overwrites the first.
    // Deferred improvement: Key it by tab.
    private let record: WebContentFreezeRecord
    private let applicationState: @MainActor () -> UIApplication.State
    private let notificationCenter: NotificationCenter
    private let date: () -> Date
    /// WebKit reports a hang 3 seconds after the message it is waiting on, so an attempt this recent is the one that
    /// triggered the report and marks when the user actually got stuck; the extra second covers a late callback.
    private static let attemptWindow: TimeInterval = 4
    /// A "responsive" callback that does not end the freeze within this time was not a recovery: the user left the
    /// tab or the app.
    private static let leaveThreshold: TimeInterval = 2
    private var lastAttemptDate: Date?
    private var lastResponsiveDate: Date?
    private var startDate: Date?
    private var context: WebContentHealthPixel.PageContext?
    private var attempts = 0

    init(pixelFiring: (any PixelKitFiring)?,
         featureFlagger: FeatureFlagger,
         record: WebContentFreezeRecord = .init(),
         applicationState: @escaping @MainActor () -> UIApplication.State = { UIApplication.shared.applicationState },
         notificationCenter: NotificationCenter = .default,
         date: @escaping () -> Date = Date.init) {
        self.pixelFiring = pixelFiring
        self.featureFlagger = featureFlagger
        self.record = record
        self.applicationState = applicationState
        self.notificationCenter = notificationCenter
        self.date = date
        super.init()
    }

    var isFrozen: Bool { startDate != nil }

    func didBecomeUnresponsive(_ context: WebContentHealthPixel.PageContext) {
        guard featureFlagger.isFeatureOn(.tabTerminationTelemetry), !isFrozen else { return }
        let now = date()
        if let lastAttemptDate, now.timeIntervalSince(lastAttemptDate) <= Self.attemptWindow {
            startDate = lastAttemptDate
        } else {
            startDate = now
        }
        self.context = context
        attempts = 0
        record.startDate = startDate
        record.backgroundDate = applicationState() == .background ? now : nil
        record.attempts = 0
        record.context = context
        notificationCenter.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        pixelFiring?.fire(WebContentHealthPixel.unresponsive(context: context, appState: appState), frequency: .dailyAndCount)
    }

    /// A reload or navigation the user started. Counted as an escape attempt while the page is frozen; otherwise
    /// remembered, since it may be the one WebKit is about to report a hang for.
    func didAttemptNavigation() {
        guard isFrozen else {
            lastAttemptDate = date()
            return
        }
        attempts += 1
        if ownsRecord {
            record.attempts = attempts
        }
    }

    /// WebKit also reports "responsive" when it merely stops waiting, for example on tab teardown or when the app
    /// goes to the background, so recovery counts only once the page answers a trivial script.
    func processDidBecomeResponsive(probe: (@escaping (Bool) -> Void) -> Void) {
        guard isFrozen else { return }
        lastResponsiveDate = date()
        let probedFreeze = startDate
        probe { [weak self] answered in
            guard answered, let self, startDate == probedFreeze else { return }
            end(.recovered)
        }
    }

    func end(_ outcome: Outcome) {
        guard let startDate, let context else { return }
        // Another tab's freeze may have taken the record since.
        if ownsRecord {
            record.clear()
        }
        self.startDate = nil
        notificationCenter.removeObserver(self)
        let duration = DurationBucket(seconds: date().timeIntervalSince(startDate))
        let leftTab = lastResponsiveDate.map { date().timeIntervalSince($0) > Self.leaveThreshold } ?? false
        lastResponsiveDate = nil
        pixelFiring?.fire(WebContentHealthPixel.unresponsiveResult(outcome: outcome,
                                                                   duration: duration,
                                                                   attempts: AttemptsBucket(attempts),
                                                                   appState: appState,
                                                                   leftTab: leftTab,
                                                                   context: context),
                          frequency: .dailyAndCount)
    }

    /// Reports the freeze the previous run exited in the middle of, if any. Call once per launch.
    /// Doesn't support multiple freezing tabs.
    static func reportFreezeEndedWithApp(record: WebContentFreezeRecord = .init(),
                                         pixelFiring: (any PixelKitFiring)? = PixelKit.shared,
                                         featureFlagger: FeatureFlagger) {
        guard let startDate = record.startDate, let context = record.context else {
            record.clear()
            return
        }
        let backgroundDate = record.backgroundDate
        let isBackground = backgroundDate != nil
        let attempts = record.attempts
        record.clear()
        guard featureFlagger.isFeatureOn(.tabTerminationTelemetry) else { return }
        let duration = backgroundDate.map { DurationBucket(seconds: $0.timeIntervalSince(startDate)) } ?? .unknown
        pixelFiring?.fire(WebContentHealthPixel.unresponsiveResult(outcome: .appEnded,
                                                                   duration: duration,
                                                                   attempts: AttemptsBucket(attempts),
                                                                   appState: isBackground ? "background" : "foreground",
                                                                   leftTab: isBackground,
                                                                   context: context),
                          frequency: .dailyAndCount)
    }

    @objc private func appDidEnterBackground() {
        guard ownsRecord else { return }
        record.backgroundDate = date()
    }

    @objc private func appWillEnterForeground() {
        guard ownsRecord else { return }
        record.backgroundDate = nil
    }

    /// The record is one slot for all tabs; a later freeze in another tab takes it over.
    private var ownsRecord: Bool {
        startDate != nil && record.startDate == startDate
    }

    private var appState: String {
        applicationState() == .background ? "background" : "foreground"
    }
}
