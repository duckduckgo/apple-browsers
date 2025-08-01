//
//  HotspotDetectionService.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Combine
import Common
import Foundation
import os.log

/// Represents the current state of hotspot connectivity
public enum HotspotConnectivityState: String, Equatable {
    /// Unknown state - default when no subscribers or initial state
    case unknown
    /// Connected to regular internet, no hotspot authentication required
    case connected
    /// Hotspot authentication required (captive portal detected)
    case hotspotAuth
}

/// Protocol for hotspot detection service that monitors internet connectivity
protocol HotspotDetectionServiceProtocol {
    /// Current connectivity state
    var currentState: HotspotConnectivityState { get }

    /// Publisher that emits connectivity state changes
    var statePublisher: AnyPublisher<HotspotConnectivityState, Never> { get }
}

/// Service that continuously monitors internet connectivity to detect hotspot authentication requirements
final class HotspotDetectionService: HotspotDetectionServiceProtocol {

    // MARK: - Private Properties

    @PublishedAfter private var currentStatePublished: HotspotConnectivityState = .unknown
    private var monitoringTask: Task<Never, any Error>?
    private let sleeper: Sleeper
    private var subscriptionCounter = 0 {
        didSet {
            updateMonitoringState()
        }
    }

    private let checkInterval: TimeInterval = 5.0 // Check every 5 seconds

    private var testURL: URL {
#if DEBUG && !APPSTORE
        return HotspotDetectionDebugSettings.shared.connectivityCheckURL
#else
        return URL(string: "http://detectportal.firefox.com/success.txt")!
#endif
    }

    // MARK: - Public Interface

    var currentState: HotspotConnectivityState {
        currentStatePublished
    }

    var statePublisher: AnyPublisher<HotspotConnectivityState, Never> {
        $currentStatePublished
            .handleEvents(
                receiveSubscription: { [weak self] _ in
                    self?.didReceiveSubscription()
                },
                receiveCancel: { [weak self] in
                    self?.didReceiveCancel()
                }
            )
            .eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(sleeper: Sleeper = .default) {
        self.sleeper = sleeper
        Logger.general.debug("HotspotDetectionService initialized")
    }

    deinit {
        monitoringTask?.cancel()
        Logger.general.debug("HotspotDetectionService deinitialized")
    }

    // MARK: - Private Methods

    private func didReceiveSubscription() {
        subscriptionCounter += 1
        Logger.general.debug("HotspotDetectionService subscription added, count: \(self.subscriptionCounter)")
    }

    private func didReceiveCancel() {
        subscriptionCounter -= 1
        Logger.general.debug("HotspotDetectionService subscription cancelled, count: \(self.subscriptionCounter)")
    }

    private func updateMonitoringState() {
        if subscriptionCounter > 0 {
            startMonitoring()
        } else {
            stopMonitoring()
            // Reset to unknown when no subscribers
            currentStatePublished = .unknown
        }
    }

    private func startMonitoring() {
        guard monitoringTask == nil else { return }

        Logger.general.debug("Starting hotspot detection monitoring")

        monitoringTask = Task.periodic(interval: checkInterval, sleeper: sleeper) { [weak self] in
            await self?.checkConnectivity()
        }
    }

    private func stopMonitoring() {
        Logger.general.debug("Stopping hotspot detection monitoring")
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func checkConnectivity() async {
        Logger.general.debug("HotspotDetectionService checking connectivity to: \(self.testURL.absoluteString)")
        do {
            let (data, response) = try await URLSession.shared.data(from: testURL)

            if let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode) {

                let responseText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = String(responseText?.prefix(50) ?? "")

                Logger.general.debug("HotspotDetectionService got status code: \(httpResponse.statusCode), text preview: '\(preview)'")

                let newState: HotspotConnectivityState
                if responseText == "success" {
                    newState = .connected
                } else {
                    // Can reach URL but response is not "success" - likely captive portal
                    newState = .hotspotAuth
                }

                // Only publish changes, not all updates
                if currentStatePublished != newState {
                    Logger.general.debug("HotspotDetectionService state changed: \(newState.rawValue)")
                    currentStatePublished = newState
                }
            } else if let httpResponse = response as? HTTPURLResponse {
                Logger.general.debug("HotspotDetectionService got status code \(httpResponse.statusCode)")
            }
        } catch {
            // Network error - could be no connection or other issues
            Logger.general.debug("HotspotDetectionService caught error: \(error), current state: \(self.currentStatePublished.rawValue)")
            // Only change state if we were previously connected
            if self.currentStatePublished == .connected {
                Logger.general.debug("HotspotDetectionService connectivity lost: \(error)")
                self.currentStatePublished = .unknown
            } else {
                Logger.general.debug("HotspotDetectionService not changing state from \(self.currentStatePublished.rawValue) due to error")
            }
        }
    }
}
