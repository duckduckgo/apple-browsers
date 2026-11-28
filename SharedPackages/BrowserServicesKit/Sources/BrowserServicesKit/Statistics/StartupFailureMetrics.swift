//
//  StartupFailureMetrics.swift
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
import Combine
import PixelKit
import PrivacyConfig

public protocol StartupFailureInstrumentation {
    func configure(featureFlagger: any FeatureFlagger, feature: any FeatureFlagDescribing)
    func recordFailure()
    func recordUserReturnedToApp()
    func recordSuccessfulStartup()
}

/// Counts startup failure episodes without identifying installations in the pixels.
/// A new episode is allowed only after the app has successfully started.
public final class StartupFailureMetrics: StartupFailureInstrumentation {

    static let enabledKey = "startupFailureMetricsEnabled"

    private struct State: Codable {
        let firstFailureDate: Date
        var didReportReturn = false
        // Earlier builds kept completed episodes on disk.
        var didSuccessfullyStart: Bool?
    }

    private let storageURLProvider: () -> URL?
    private let pixelFiringProvider: () -> (any PixelFiring)?
    private let defaults: UserDefaults
    private let dateProvider: () -> Date
    private let lock = NSLock()
    private var featureFlagCancellable: AnyCancellable?
    private var didFailInThisProcess = false

    /// The app lifecycle is constructed before PixelKit is configured, so resolve the client at event time.
    public convenience init(defaults: UserDefaults = .standard, pixelFiring: @escaping () -> (any PixelFiring)? = { PixelKit.shared }) {
        self.init(
            storageURL: {
                Self.makeStorageURL(
                    applicationSupportDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                    bundleIdentifier: Bundle.main.bundleIdentifier
                )
            },
            pixelFiring: pixelFiring,
            defaults: defaults
        )
    }

    init(storageURL: @escaping () -> URL?, pixelFiring: @escaping () -> (any PixelFiring)?, defaults: UserDefaults,
         dateProvider: @escaping () -> Date = Date.init) {
        self.storageURLProvider = storageURL
        self.pixelFiringProvider = pixelFiring
        self.defaults = defaults
        self.dateProvider = dateProvider
    }

    /// Early startup failures use the last resolved flag value, defaulting to off.
    /// Once the flagger is available, keep that value current for this process and the next launch.
    public func configure(featureFlagger: any FeatureFlagger, feature: any FeatureFlagDescribing) {
        featureFlagCancellable = featureFlagger.updatesPublisher.sink { [weak self] in
            self?.updateFeatureFlag(featureFlagger: featureFlagger, feature: feature)
        }
        updateFeatureFlag(featureFlagger: featureFlagger, feature: feature)
    }

    private func updateFeatureFlag(featureFlagger: any FeatureFlagger, feature: any FeatureFlagDescribing) {
        lock.lock()
        defer { lock.unlock() }
        let isEnabled = featureFlagger.isFeatureOn(for: feature)
        if defaults.bool(forKey: Self.enabledKey) != isEnabled {
            defaults.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    static func makeStorageURL(applicationSupportDirectory: URL?, bundleIdentifier: String?) -> URL? {
        guard let applicationSupportDirectory, let bundleIdentifier else { return nil }
        return applicationSupportDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("startup-failure-metrics.json")
    }

    /// Called before deliberately exiting because startup cannot complete.
    /// Repeated failures in an open episode neither emit another pixel nor reset its age.
    public func recordFailure() {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        let pixelFiring = pixelFiringProvider()
        lock.lock()
        do {
            defer { lock.unlock() }
            guard defaults.bool(forKey: Self.enabledKey) else { return }
            didFailInThisProcess = true
            guard pixelFiring != nil, let storageURL = storageURLProvider() else { return }
            guard try readState(from: storageURL) == nil else { return }
            try writeState(State(firstFailureDate: dateProvider()), to: storageURL)
        } catch {
            // Measurement must not introduce another failure or count an episode we cannot persist.
            return
        }

        pixelFiring?.fire(StartupFailurePixel.failure, frequency: .standard, options: .withRetry)
    }

    /// Reports the first observed return after a recorded failure.
    /// This does not rearm failure reporting: only a successful startup closes the episode.
    public func recordUserReturnedToApp() {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        let pixelFiring = pixelFiringProvider()
        lock.lock()
        let daysBucket: StartupFailurePixel.DayBucket?
        do {
            defer { lock.unlock() }
            guard defaults.bool(forKey: Self.enabledKey), !didFailInThisProcess, pixelFiring != nil, let storageURL = storageURLProvider(),
                  var state = try readState(from: storageURL),
                  !state.didReportReturn else { return }
            daysBucket = daysSinceFailureBucket(from: state.firstFailureDate)
            state.didReportReturn = true
            // Persist before sending so another launch cannot count the same return twice.
            try writeState(state, to: storageURL)
        } catch {
            return
        }

        pixelFiring?.fire(StartupFailurePixel.returned(daysBucket: daysBucket), frequency: .standard, options: .withRetry)
    }

    /// Reports recovery and closes the episode when startup completes.
    public func recordSuccessfulStartup() {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        let pixelFiring = pixelFiringProvider()
        lock.lock()
        let daysBucket: StartupFailurePixel.DayBucket?
        do {
            defer { lock.unlock() }
            guard defaults.bool(forKey: Self.enabledKey), !didFailInThisProcess, pixelFiring != nil, let storageURL = storageURLProvider(),
                  let state = try readState(from: storageURL),
                  state.didReportReturn else { return }
            daysBucket = daysSinceFailureBucket(from: state.firstFailureDate)
            try FileManager.default.removeItem(at: storageURL)
        } catch {
            // Keep the episode open if its file cannot be removed.
            return
        }

        pixelFiring?.fire(StartupFailurePixel.recovered(daysBucket: daysBucket), frequency: .standard, options: .withRetry)
    }

    private func readState(from url: URL) throws -> State? {
        do {
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
            return state.didSuccessfullyStart == true ? nil : state
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func writeState(_ state: State, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    private func daysSinceFailureBucket(from failureDate: Date) -> StartupFailurePixel.DayBucket? {
        let elapsed = dateProvider().timeIntervalSince(failureDate)
        guard elapsed.isFinite, elapsed >= 0,
              let days = Int(exactly: (elapsed / (24 * 60 * 60)).rounded(.down)) else { return nil }
        return StartupFailurePixel.DayBucket.containing(days)
    }
}

enum StartupFailurePixel: PixelKit.Event {
    enum DayBucket: Int, CaseIterable {
        case sameDay = 0
        case oneDay = 1
        case threeDays = 3
        case fiveDays = 5
        case eightDays = 8
        case thirteenDays = 13
        case twentyOneDays = 21

        static func containing(_ days: Int) -> Self? {
            allCases.last { $0.rawValue <= days }
        }

        var label: String {
            self == .sameDay ? "0" : "\(rawValue)+"
        }
    }

    case failure
    case returned(daysBucket: DayBucket?)
    case recovered(daysBucket: DayBucket?)

    var name: String {
        let base: String
        switch self {
        case .failure:
            base = "startup_failure"
        case .returned:
            base = "startup_failure_returned"
        case .recovered:
            base = "startup_failure_recovered"
        }
        #if os(macOS)
        return base + "_macos"
        #else
        return base
        #endif
    }

    var namePrefix: PixelKitNamePrefix { .none }
    var standardParameters: [PixelKitStandardParameter]? { nil }

    var parameters: [String: String]? {
        switch self {
        case .failure:
            return nil
        case .returned(let daysBucket), .recovered(let daysBucket):
            return daysBucket.map { ["days_count": $0.label] }
        }
    }
}
