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

extension Logger {
    static let adClickExternalOpenDetector = Logger(subsystem: "AdClickExternalOpenDetector", category: "")
}

/// Detects and mitigates the issue described in https://app.asana.com/1/137249556945/project/1205842942115003/task/1209365034718375
/// This is a best effort attempt that could be ineffective when the connection is particularly slow and the requests need a long time to load
final class AdClickExternalOpenDetector {

    private let operationTimeout: TimeInterval // 2s is enough on a fast connection
    private var operationStartDate: Date?
    private var state: AdClickState = .unknown
    private var tabID: String
    public typealias AdClickExternalOpenDetectorCompletionBlock = () -> Void
    public var mitigationHandler: AdClickExternalOpenDetectorCompletionBlock?

    private enum AdClickState: String {
        case unknown
        case startNavigation
        case failNavigation
        case leaveApp
        case finishNavigation
    }

    init(tabID: String, operationTimeout: TimeInterval = .seconds(6)) {
        self.tabID = tabID
        self.operationTimeout = operationTimeout
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // Events handlers

    @objc private func appDidEnterBackground() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) - App entered background")
        changeState(.leaveApp)
    }

    public func startNavigation() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) App started navigation")
        changeState(.startNavigation)
    }

    public func failNavigation() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) App failed navigation")
        changeState(.failNavigation)
    }

    public func finishNavigation() {
        changeState(.finishNavigation)
    }

    // State machine

    private func changeState(_ newState: AdClickState) {
        var timeDifference: String = "Nil"
        if let operationStartDate = operationStartDate {
            timeDifference = Date().timeIntervalSince(operationStartDate).description
        }
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) State changed from \(self.state.rawValue) to \(newState.rawValue) - Timer: \(timeDifference)")

        guard !isTimeoutExpired() else {
            Logger.adClickExternalOpenDetector.debug("\(self.tabID) Timeout expired")
            reset()
            return
        }

        /*
         The only valid event sequence triggering a mitigation is:
         - unknown
         - startNavigation
         - failNavigation
         - leaveApp
         Any other sequence reset the state
         */

        switch state {
        case .unknown:
            if newState == .startNavigation {
                operationStartDate = Date()
                state = newState
            } else {
                reset()
            }
        case .startNavigation:
            if newState == .failNavigation {
                state = newState
            } else {
                reset()
            }
        case .failNavigation:
            if newState == .leaveApp {
                state = newState
                mitigate()
            } else {
                reset()
            }
        case .leaveApp:
            reset()
        case .finishNavigation:
            reset()
        }
    }

    private func isTimeoutExpired() -> Bool {
        guard let operationStartDate = operationStartDate else { return false }
        return Date().timeIntervalSince(operationStartDate) > operationTimeout
    }

    private func reset() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) Resetting state")
        operationStartDate = nil
        state = .unknown
    }

    private func mitigate() {
        Logger.adClickExternalOpenDetector.debug("\(self.tabID) Mitigating")
        reset()
        mitigationHandler?()
    }
}
