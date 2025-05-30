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

/// Mitigation for https://app.asana.com/1/137249556945/project/1205842942115003/task/1209365034718375
final class AdClickExternalOpenDetector {

    private let operationTimeout: TimeInterval = .seconds(4)
    private var operationStartDate: Date?
    private var state: AdClickState = .unknown
    public var tabID: String
    public typealias AdClickExternalOpenDetectorCompletionBlock = () -> Void
    public var mitigationHandler: AdClickExternalOpenDetectorCompletionBlock?

    private enum AdClickState: String {
        case unknown
        case startNavigation
        case failNavigation
        case leaveApp
        case finishNavigation
    }

    init(tabID: String) {
        self.tabID = tabID
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

    // events handlers

    @objc private func appDidEnterBackground() {
        Logger.adClickExternalOpenDetector.log("\(self.tabID, privacy: .public) - App entered background")
        changeState(.leaveApp)
    }

    public func startNavigation() {
        Logger.adClickExternalOpenDetector.log("\(self.tabID, privacy: .public) App started navigation")
        changeState(.startNavigation)
    }

    public func failNavigation() {
        Logger.adClickExternalOpenDetector.log("\(self.tabID, privacy: .public) App failed navigation")
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
        Logger.adClickExternalOpenDetector.log("\(self.tabID, privacy: .public) State changed from \(self.state.rawValue, privacy: .public) to \(newState.rawValue, privacy: .public) - Timer: \(timeDifference)")

        guard !isTimeoutExpired() else {
            Logger.adClickExternalOpenDetector.log("\(self.tabID, privacy: .public) Timeout expired")
            reset()
            return
        }

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
        Logger.adClickExternalOpenDetector.log("\(self.tabID, privacy: .public) Resetting state")
        operationStartDate = nil
        state = .unknown
    }

    private func mitigate() {
        Logger.adClickExternalOpenDetector.log("\(self.tabID, privacy: .public) Mitigating")
        reset()
        mitigationHandler?()
    }
}
