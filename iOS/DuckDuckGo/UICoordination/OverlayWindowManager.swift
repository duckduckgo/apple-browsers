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
import Core
import PrivacyConfig

protocol OverlayWindowManaging {

    func prepareBlankSnapshotWindow()
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
    /// Pre-built, hidden blank-snapshot window kept ready so backgrounding doesn't build the chrome on the watchdog path.
    private var preparedOverlayWindow: UIWindow?
    private var activeReasons: BlankSnapshotOverlayReason = []

    private let window: UIWindow
    private let appSettings: AppSettings
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let featureFlagger: FeatureFlagger
    private let aiChatSettings: AIChatSettings
    private let aiChatAddressBarExperience: AIChatAddressBarExperienceProviding
    private let mobileCustomization: MobileCustomization
    private let privacyStore: PrivacyStore

    init(window: UIWindow,
         appSettings: AppSettings,
         voiceSearchHelper: VoiceSearchHelperProtocol,
         featureFlagger: FeatureFlagger,
         aiChatSettings: AIChatSettings,
         aiChatAddressBarExperience: AIChatAddressBarExperienceProviding,
         mobileCustomization: MobileCustomization,
         privacyStore: PrivacyStore = PrivacyUserDefaults()) {
        self.window = window
        self.appSettings = appSettings
        self.voiceSearchHelper = voiceSearchHelper
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
        self.aiChatAddressBarExperience = aiChatAddressBarExperience
        self.mobileCustomization = mobileCustomization
        self.privacyStore = privacyStore

        registerForCacheInvalidationNotifications()
        // Seed the cache off the critical path so the first background doesn't build the chrome.
        DispatchQueue.main.async { [weak self] in
            self?.prepareBlankSnapshotWindow()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    /// Caching is only worthwhile when app lock is on (the overlay is shown until authentication) and the flag is enabled.
    private var isCachingEnabled: Bool {
        featureFlagger.isFeatureOn(.blankSnapshotCaching) && privacyStore.authenticationEnabled
    }

    func prepareBlankSnapshotWindow() {
        guard isCachingEnabled else {
            preparedOverlayWindow = nil
            return
        }
        guard overlayWindow == nil, preparedOverlayWindow == nil else { return }
        // Setting rootViewController triggers the heavy viewDidLoad now, off the suspend path.
        preparedOverlayWindow = makeOverlayWindow(with: makeBlankSnapshotViewController())
    }

    func displayBlankSnapshotWindow(for reason: BlankSnapshotOverlayReason) {
        activeReasons.insert(reason)
        guard overlayWindow == nil else { return }
        let windowToReveal: UIWindow
        if isCachingEnabled, let preparedOverlayWindow {
            windowToReveal = preparedOverlayWindow
        } else {
            windowToReveal = makeOverlayWindow(with: makeBlankSnapshotViewController())
        }
        preparedOverlayWindow = nil
        reveal(overlayWindow: windowToReveal)
    }

    func displayOverlay(with viewController: UIViewController) {
        guard overlayWindow == nil else { return }
        reveal(overlayWindow: makeOverlayWindow(with: viewController))
    }

    func removeAnyOverlay() {
        guard let overlay = overlayWindow ?? obtainOverlayWindow() else { return }
        overlay.isHidden = true
        overlayWindow = nil
        window.makeKeyAndVisible()
        activeReasons = []
        // Re-arm the cache for the next background, off the critical path.
        DispatchQueue.main.async { [weak self] in
            self?.prepareBlankSnapshotWindow()
        }
    }

    func removeBlankSnapshotWindow(for reason: BlankSnapshotOverlayReason) {
        guard !(overlayWindow?.rootViewController is AuthenticationViewController) else { return }
        activeReasons.remove(reason)
        if activeReasons.isEmpty {
            removeAnyOverlay()
        }
    }

    private func makeBlankSnapshotViewController() -> BlankSnapshotViewController {
        let blankSnapshotViewController = BlankSnapshotViewController(addressBarPosition: appSettings.currentAddressBarPosition,
                                                                      aiChatSettings: aiChatSettings,
                                                                      aiChatAddressBarExperience: aiChatAddressBarExperience,
                                                                      voiceSearchHelper: voiceSearchHelper,
                                                                      featureFlagger: featureFlagger,
                                                                      appSettings: appSettings,
                                                                      mobileCustomization: mobileCustomization)
        let isMinimalChrome = !AppWidthObserver.shared.isPad
            && window.bounds.width > window.bounds.height
        blankSnapshotViewController.useMinimalChromeLayout = AppWidthObserver.shared.isLargeWidth || isMinimalChrome
        blankSnapshotViewController.delegate = self
        return blankSnapshotViewController
    }

    private func makeOverlayWindow(with viewController: UIViewController) -> UIWindow {
        let newWindow: UIWindow
        if let windowScene = window.windowScene {
            newWindow = UIWindow(windowScene: windowScene)
        } else {
            newWindow = UIWindow(frame: window.frame)
        }
        newWindow.windowLevel = .alert
        newWindow.rootViewController = viewController
        return newWindow
    }

    private func reveal(overlayWindow windowToReveal: UIWindow) {
        overlayWindow = windowToReveal
        windowToReveal.makeKeyAndVisible()
        ThemeManager.shared.updateUserInterfaceStyle(window: windowToReveal)
        window.isHidden = true
    }

    private func obtainOverlayWindow() -> UIWindow? {
        UIApplication.shared.foregroundSceneWindows.first {
            !$0.isHidden && $0.rootViewController is BlankSnapshotViewController
        }
    }

    // MARK: - Cache invalidation

    private func registerForCacheInvalidationNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(authenticationEnabledDidChange),
                                               name: PrivacyUserDefaults.Notifications.authenticationEnabledChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(cachedOverlayInputsDidChange),
                                               name: AppUserDefaults.Notifications.addressBarPositionChanged,
                                               object: nil)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(cachedOverlayInputsDidChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }

    @objc private func authenticationEnabledDidChange() {
        preparedOverlayWindow = nil
        prepareBlankSnapshotWindow()
    }

    @objc private func cachedOverlayInputsDidChange() {
        preparedOverlayWindow = nil
        DispatchQueue.main.async { [weak self] in
            self?.prepareBlankSnapshotWindow()
        }
    }

}

extension OverlayWindowManager: BlankSnapshotViewRecoveringDelegate {

    func recoverFromPresenting(controller: BlankSnapshotViewController) {
        removeAnyOverlay()
    }

}
