//
//  OverlayWindowManager.swift
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
import BrowserServicesKit

protocol OverlayWindowManaging {

    func displayBlankSnapshotWindow(for reason: BlankSnapshotOverlayReason)
    func removeBlankSnapshotWindow(for reason: BlankSnapshotOverlayReason)

    func displayOverlay(with viewController: UIViewController)
    func removeAnyOverlay()

}

struct BlankSnapshotOverlayReason: OptionSet {

    let rawValue: Int

    static let autoClearing   = BlankSnapshotOverlayReason(rawValue: 1 << 0)
    static let authentication = BlankSnapshotOverlayReason(rawValue: 1 << 1)

}

final class OverlayWindowManager: OverlayWindowManaging {

    private var overlayWindow: UIWindow?
    private var activeReasons: BlankSnapshotOverlayReason = []

    private let window: UIWindow
    private let appSettings: AppSettings
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let featureFlagger: FeatureFlagger
    private let aiChatSettings: AIChatSettings

    init(window: UIWindow,
         appSettings: AppSettings,
         voiceSearchHelper: VoiceSearchHelperProtocol,
         featureFlagger: FeatureFlagger,
         aiChatSettings: AIChatSettings) {
        self.window = window
        self.appSettings = appSettings
        self.voiceSearchHelper = voiceSearchHelper
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
    }

    func displayBlankSnapshotWindow(for reason: BlankSnapshotOverlayReason) {
        activeReasons.insert(reason)
        let blankSnapshotViewController = BlankSnapshotViewController(addressBarPosition: appSettings.currentAddressBarPosition,
                                                                      aiChatSettings: aiChatSettings,
                                                                      voiceSearchHelper: voiceSearchHelper,
                                                                      featureFlagger: featureFlagger,
                                                                      appSettings: appSettings)
        blankSnapshotViewController.delegate = self
        displayOverlay(with: blankSnapshotViewController)
    }

    func displayOverlay(with viewController: UIViewController) {
        guard overlayWindow == nil else { return }
        overlayWindow = UIWindow(frame: window.frame)
        overlayWindow?.windowLevel = .alert
        overlayWindow?.rootViewController = viewController
        overlayWindow?.makeKeyAndVisible()
        ThemeManager.shared.updateUserInterfaceStyle(window: overlayWindow)
        window.isHidden = true
    }

    func removeAnyOverlay() {
        guard let overlay = overlayWindow ?? obtainOverlayWindow() else { return }
        overlay.isHidden = true
        overlayWindow = nil
        window.makeKeyAndVisible()
        activeReasons = []
    }

    func removeBlankSnapshotWindow(for reason: BlankSnapshotOverlayReason) {
        guard !(overlayWindow?.rootViewController is AuthenticationViewController) else { return }
        activeReasons.remove(reason)
        if activeReasons.isEmpty {
            removeAnyOverlay()
        }
    }

    private func obtainOverlayWindow() -> UIWindow? {
        UIApplication.shared.foregroundSceneWindows.first {
            $0.rootViewController is BlankSnapshotViewController
        }
    }

}

extension OverlayWindowManager: BlankSnapshotViewRecoveringDelegate {

    func recoverFromPresenting(controller: BlankSnapshotViewController) {
        removeAnyOverlay()
    }

}
