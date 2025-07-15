//
//  AutoClearService.swift
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

import UIKit

protocol AutoClearServiceProtocol {

    var autoClearTask: Task<Void, Never>? { get }
    var isClearingEnabled: Bool { get }
    func waitForDataCleared() async

}

final class AutoClearService: AutoClearServiceProtocol {

    private let autoClear: AutoClearing
    private let overlayWindowManager: OverlayWindowManaging
    private let application: UIApplication

    private(set) var autoClearTask: Task<Void, Never>?

    var isClearingEnabled: Bool {
        autoClear.isClearingEnabled
    }

    init(autoClear: AutoClearing,
         overlayWindowManager: OverlayWindowManaging,
         application: UIApplication = UIApplication.shared) {
        self.autoClear = autoClear
        self.overlayWindowManager = overlayWindowManager
        self.application = application

        autoClearTask = Task {
            await autoClear.clearDataIfEnabled(launching: true, applicationState: .init(with: application.applicationState))
        }
    }

    // MARK: - Resume

    func resume() {
        if autoClear.isClearingDue {
            autoClearTask = Task {
                await autoClear.clearDataDueToTimeExpired(applicationState: .active)
            }
        } else {
            overlayWindowManager.removeNonAuthenticationOverlay()
        }
    }

    // MARK: - Suspend

    func suspend() {
        if autoClear.isClearingEnabled {
            overlayWindowManager.displayBlankSnapshotWindow()
        }
        autoClear.startClearingTimer(Date().timeIntervalSince1970)
    }

    // MARK: -

    @MainActor
    func waitForDataCleared() async {
        await autoClearTask?.value
        overlayWindowManager.removeNonAuthenticationOverlay()
    }

}
