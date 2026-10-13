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
/// it lasted and how often the user tried to get out. Releasing the monitor ends the freeze as `closed`. Main thread.
final class WebContentFreezeMonitor {

    enum Outcome: String {
        case recovered
        case closed
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
    private let record: WebContentFreezeRecord
    private let applicationState: () -> UIApplication.State
    private let notificationCenter: NotificationCenter
    private let date: () -> Date
    private var observers = [any NSObjectProtocol]()
    private var startDate: Date?
    private var context: WebContentHealthPixel.PageContext?
    private var attempts = 0

    init(pixelFiring: (any PixelKitFiring)?,
         featureFlagger: FeatureFlagger,
         record: WebContentFreezeRecord = .init(),
         applicationState: @escaping () -> UIApplication.State = { UIApplication.shared.applicationState },
         notificationCenter: NotificationCenter = .default,
         date: @escaping () -> Date = Date.init) {
        self.pixelFiring = pixelFiring
        self.featureFlagger = featureFlagger
        self.record = record
        self.applicationState = applicationState
        self.notificationCenter = notificationCenter
        self.date = date
        observers = [
            notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
                guard let self, isFrozen else { return }
                record.backgroundDate = date()
            },
            notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
                self?.record.backgroundDate = nil
            }
        ]
    }

    deinit {
        observers.forEach { notificationCenter.removeObserver($0) }
        end(.closed)
    }

    var isFrozen: Bool { startDate != nil }

    func didBecomeUnresponsive(_ context: WebContentHealthPixel.PageContext) {
        guard featureFlagger.isFeatureOn(.tabTerminationTelemetry), !isFrozen else { return }
        let now = date()
        startDate = now
        self.context = context
        attempts = 0
        record.startDate = now
        record.backgroundDate = nil
        record.attempts = 0
        record.context = context
        pixelFiring?.fire(WebContentHealthPixel.unresponsive(context: context, appState: appState), frequency: .dailyAndCount)
    }

    /// A reload or navigation the user started while the page was frozen.
    func didAttemptNavigation() {
        guard isFrozen else { return }
        attempts += 1
        record.attempts = attempts
    }

    func end(_ outcome: Outcome) {
        guard let startDate, let context else { return }
        self.startDate = nil
        record.clear()
        let duration = DurationBucket(seconds: date().timeIntervalSince(startDate))
        pixelFiring?.fire(WebContentHealthPixel.unresponsiveResult(outcome: outcome,
                                                                   duration: duration,
                                                                   attempts: AttemptsBucket(attempts),
                                                                   appState: appState,
                                                                   context: context),
                          frequency: .dailyAndCount)
    }

    /// The tab switcher's first preview snapshot timed out, so the page may be frozen whether or not WebKit said so.
    func previewSnapshotTimedOut(retry: WebContentHealthPixel.SnapshotRetry) {
        guard featureFlagger.isFeatureOn(.tabTerminationTelemetry) else { return }
        pixelFiring?.fire(WebContentHealthPixel.previewSnapshotTimeout(retry: retry, unresponsive: isFrozen, appState: appState),
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
        let attempts = record.attempts
        record.clear()
        guard featureFlagger.isFeatureOn(.tabTerminationTelemetry) else { return }
        let duration = backgroundDate.map { DurationBucket(seconds: $0.timeIntervalSince(startDate)) } ?? .unknown
        pixelFiring?.fire(WebContentHealthPixel.unresponsiveResult(outcome: .appEnded,
                                                                   duration: duration,
                                                                   attempts: AttemptsBucket(attempts),
                                                                   appState: backgroundDate == nil ? "foreground" : "background",
                                                                   context: context),
                          frequency: .dailyAndCount)
    }

    private var appState: String {
        applicationState() == .background ? "background" : "foreground"
    }
}
