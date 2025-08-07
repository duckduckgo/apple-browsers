//
//  AdClickExternalOpenDetector.swift
//  DuckDuckGo
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

import Foundation
import UIKit
import os.log
import Combine
import WebKit
extension Logger {
    static let adClickExternalOpenDetector = Logger(subsystem: "AdClickExternalOpenDetector", category: "")
}

/**
 * This class detects and mitigates a specific navigation issue with redirects to external applications.
 * It implements a state machine that monitors navigation events and app background transitions to identify when we leave the app due to navigation and need to emulate Safari's behaviour: tab cleanup or URL updates.
 * This is to ensure correct URL is being presented to the user, and that no "empty new tabs" are being left open in the app post-navigation.
 *
 * We handle two scenarios: for same-tab navigations and for navigation that are being done in a new tab.
 *
 * The detector follows a specific event sequence to trigger mitigation:
 * 1. Navigation to external domain starts.
 * 2. Navigation fails with a specific error (redirect doesn't complete normally)
 * 3. App enters background (indicating external app launch attempt)
 *
 * When this sequence is detected within the timeout period, the mitigation handler is called.
 *
 * Related issue: https://app.asana.com/1/137249556945/project/1205842942115003/task/1209365034718375
 */
final class AdClickExternalOpenDetector {

    private let operationTimeout: TimeInterval
    private var navigationFailedDate: Date?
    private let tabID: String
    private var cancellables = Set<AnyCancellable>()
    public typealias AdClickExternalOpenDetectorCompletionBlock = () -> Void
    public var mitigationHandler: AdClickExternalOpenDetectorCompletionBlock?
    private var skipDetection: Bool = false

    private var state: AdClickState = .unknown {
        didSet {
            if state == .failNavigation {
                navigationFailedDate = Date()
            }
        }
    }

    private enum AdClickState: String {
        case unknown
        case startNavigation
        case failNavigation
        case leaveApp
        case finishNavigation
    }

    init(tabID: String = UUID().uuidString, operationTimeout: TimeInterval = .seconds(4)) {
        self.tabID = tabID
        self.operationTimeout = operationTimeout

        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.appDidEnterBackground()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.appDidBecomeActive()
            }
            .store(in: &cancellables)
    }

    deinit {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) Deallocated")
    }

    // MARK: - Event Handlers

    func appDidEnterBackground() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) App entered background")
        changeState(.leaveApp)
    }

    /// We generally don't care about `didBecomeActiveNotification`, but if the app goes in background and is brought forward very fast (cmd+tab on iPad) then `didEnterBackgroundNotification` notification is not fired and we don't mitigate the issue.
    func appDidBecomeActive() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) App did become active")
        changeState(.leaveApp)
    }

    public func startNavigation() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) Navigation started")

        guard !skipDetection else {
            Logger.adClickExternalOpenDetector.debug("\(self.tabID) Skipping detection")
            reset()
            skipDetection = false
            return
        }

        changeState(.startNavigation)
    }

    public func failNavigation(error: Error) {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) Navigation failed - Error: \(error.localizedDescription)")
        
        guard isRelevantWebKitError(error) else {
            reset()
            return
        }
        
        changeState(.failNavigation)
    }

    public func finishNavigation() {
        changeState(.finishNavigation)
    }

    public func invalidateForUserInitiated() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) User interaction detected, invalidating")
        reset()
        skipDetection = true
    }

    // MARK: - State Machine

    /// Valid sequence: unknown → startNavigation → failNavigation → leaveApp
    /// Any other sequence resets the state
    private func changeState(_ newState: AdClickState) {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) State: \(self.state.rawValue) → \(newState.rawValue)")

        switch (state, newState) {
        case (.unknown, .startNavigation),
             (.startNavigation, .failNavigation):
            state = newState
            
        case (.failNavigation, .leaveApp):
            state = newState
            attemptMitigation()
            
        default:
            reset()
        }
    }
    
    private func attemptMitigation() {
        if !isTimeoutExpired() {
            mitigate()
        } else {
            Logger.adClickExternalOpenDetector.debug("\(self.tabID) Timeout expired, resetting")
            reset()
        }
    }

    private func isTimeoutExpired() -> Bool {
        guard let navigationFailedDate = navigationFailedDate else { return false }
        return Date().timeIntervalSince(navigationFailedDate) > operationTimeout
    }

    // MARK: - Private Helpers
    
    private func isRelevantWebKitError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == WKError.WebKitErrorDomain && nsError.code == WKError.Code.frameLoadInterruptedByPolicyChange.rawValue
    }
    
    func reset() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) Resetting state")
        navigationFailedDate = nil
        state = .unknown
    }

    private func mitigate() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) mitigating")
        reset()
        mitigationHandler?()
    }
}
