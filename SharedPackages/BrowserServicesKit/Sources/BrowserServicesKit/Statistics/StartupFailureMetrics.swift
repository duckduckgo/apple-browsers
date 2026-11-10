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
    func recordReturn()
    func recordSuccessfulStartup()
}

/// Counts startup failure episodes without identifying installations in the pixels.
/// A new episode is allowed only after the app has successfully started.
public final class StartupFailureMetrics: StartupFailureInstrumentation {

    static let enabledKey = "startupFailureMetricsEnabled"

    private struct State: Codable {
        let firstFailureDate: Date
        var didReportReturn = false
        var didSuccessfullyStart = false
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
            let state = try readState(from: storageURL)
            guard state == nil || state?.didSuccessfullyStart == true else { return }
            try writeState(State(firstFailureDate: dateProvider()), to: storageURL)
        } catch {
            // Measurement must not introduce another failure or count an episode we cannot persist.
            return
        }

        pixelFiring?.fire(StartupFailurePixel.failure, frequency: .standard)
    }

    /// Reports the first launch attempt after a recorded failure.
    /// This does not rearm failure reporting: only a successful startup closes the episode.
    public func recordReturn() {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        let pixelFiring = pixelFiringProvider()
        lock.lock()
        let daysSinceFailure: String
        do {
            defer { lock.unlock() }
            guard defaults.bool(forKey: Self.enabledKey), !didFailInThisProcess, pixelFiring != nil, let storageURL = storageURLProvider(),
                  var state = try readState(from: storageURL),
                  !state.didReportReturn, !state.didSuccessfullyStart else { return }
            daysSinceFailure = Self.daysSinceFailure(from: state.firstFailureDate, to: dateProvider())
            state.didReportReturn = true
            // Persist before sending so another launch cannot count the same return twice.
            try writeState(state, to: storageURL)
        } catch {
            return
        }

        pixelFiring?.fire(StartupFailurePixel.returned(daysSinceFailure: daysSinceFailure), frequency: .standard)
    }

    /// Reports recovery and closes the episode once the browser is ready for user interaction.
    public func recordSuccessfulStartup() {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        let pixelFiring = pixelFiringProvider()
        lock.lock()
        let daysSinceFailure: String
        do {
            defer { lock.unlock() }
            guard defaults.bool(forKey: Self.enabledKey), !didFailInThisProcess, pixelFiring != nil, let storageURL = storageURLProvider(),
                  var state = try readState(from: storageURL),
                  state.didReportReturn, !state.didSuccessfullyStart else { return }
            daysSinceFailure = Self.daysSinceFailure(from: state.firstFailureDate, to: dateProvider())
            state.didSuccessfullyStart = true
            try writeState(state, to: storageURL)
        } catch {
            // Keep the episode open if closing it cannot be persisted.
            return
        }

        pixelFiring?.fire(StartupFailurePixel.recovered(daysSinceFailure: daysSinceFailure), frequency: .standard)
    }

    private func readState(from url: URL) throws -> State? {
        do {
            return try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func writeState(_ state: State, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    private static func daysSinceFailure(from failureDate: Date, to returnDate: Date) -> String {
        let elapsed = returnDate.timeIntervalSince(failureDate)
        guard elapsed.isFinite, elapsed >= 0 else { return "unknown" }
        guard elapsed < 7 * 24 * 60 * 60 else { return "7+" }
        return String(Int(elapsed / (24 * 60 * 60)))
    }
}

enum StartupFailurePixel: PixelKit.Event {
    case failure
    case returned(daysSinceFailure: String)
    case recovered(daysSinceFailure: String)

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
        case .returned(let daysSinceFailure), .recovered(let daysSinceFailure):
            return ["days_since_first_failure": daysSinceFailure]
        }
    }
}
