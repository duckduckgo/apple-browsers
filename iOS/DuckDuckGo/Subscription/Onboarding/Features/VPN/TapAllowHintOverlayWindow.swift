//
//  TapAllowHintOverlayWindow.swift
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

import SwiftUI
import UIKit
import DesignResourcesKit
import UIComponents

/// Decides whether the "Tap allow" pointer should be visible. The screen forwards lifecycle and VPN
/// events; this publishes the single ``shouldShowHint`` the view maps onto ``TapAllowHintOverlayWindow``.
///
/// The hint is shown only while the customer has tapped "Turn On VPN" and no VPN configuration is
/// installed yet — i.e. while the system permission dialog is the reason the app lost focus.
@MainActor
final class TapAllowHintCoordinator: ObservableObject {

    @Published private(set) var shouldShowHint = false

    private var didTapStart = false

    private var configurationCheck: Task<Void, Never>?

    func startTapped() {
        configurationCheck?.cancel()
        didTapStart = true
        shouldShowHint = false
    }

    func appWillResignActive(isVPNConfigured: @escaping () async -> Bool) {
        reevaluate(isVPNConfigured: isVPNConfigured)
    }

    func appDidBecomeActive(isVPNConfigured: @escaping () async -> Bool) {
        reevaluate(isVPNConfigured: isVPNConfigured)
    }

    func appDidEnterBackground() {
        shouldShowHint = false
    }

    func turnOnFinished() {
        reset()
    }

    func connected() {
        reset()
    }

    func permissionDenied() {
        reset()
    }

    func disappeared() {
        reset()
    }

    /// Clears the hint, then re-shows it only if the customer has tapped "Turn On VPN" and the
    /// configuration still isn't installed.
    private func reevaluate(isVPNConfigured: @escaping () async -> Bool) {
        configurationCheck?.cancel()
        shouldShowHint = false
        guard didTapStart else { return }
        configurationCheck = Task {
            let isInstalled = await isVPNConfigured()
            guard !Task.isCancelled, self.didTapStart, !isInstalled else { return }
            self.shouldShowHint = true
        }
    }

    private func reset() {
        configurationCheck?.cancel()
        didTapStart = false
        shouldShowHint = false
    }
}

/// Presents the "Tap allow" pointer in a dedicated `UIWindow`. Held by the view for
/// its lifetime; ``show()`` / ``hide()`` bracket the first-time turn-on.
@MainActor
final class TapAllowHintOverlayWindow {
    private enum Metrics {
        static let bubbleArrowHeight: CGFloat = 33
        static let bubblePillHeight: CGFloat = 44
        static let bubbleHeight: CGFloat = bubbleArrowHeight + bubblePillHeight

        // Screen-centre-relative target for the arrow *tip* (the dialog is centred): its left "Allow" button.
        // No API exposes the dialog's layout, so these are hand-tuned
        static var hintOffsetX: CGFloat {
            return -77
        }
        static var hintOffsetY: CGFloat {
            if #available(iOS 26, *) { return 135 }
            return 65
        }
    }

    private var window: UIWindow?

    /// Layers the hint over the frontmost scene.
    func show() {
        guard window == nil, let scene = Self.foregroundWindowScene else { return }
        let hostingController = UIHostingController(rootView: Self.hintView)
        hostingController.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        // The system permission dialog dims the screen with a scrim that sits above `.alert`, so `.alert + 1`
        // leaves the hint rendered underneath it (dimmed).
        window.windowLevel = UIWindow.Level(rawValue: .greatestFiniteMagnitude)
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        window.rootViewController = hostingController
        window.isHidden = false
        self.window = window
        // The window is non-interactive (VoiceOver can't reach it)
        UIAccessibility.post(notification: .announcement,
                             argument: UserText.subscriptionOnboardingVPNActivationTapAllowHint)
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }

    // The system dialog is screen-centered, so position from the live screen centre (the window-sized
    // `GeometryReader`). `.position` centres the bubble, so
    // add half its height on the y axis so the arrow *tip* (its top) lands on the target.
    private static var hintView: some View {
        GeometryReader { proxy in
            FloatingPointerBubble(text: UserText.subscriptionOnboardingVPNActivationTapAllowHint,
                                  backgroundColor: Color(singleUseColor: .fireModeAccent))
                .position(x: proxy.size.width / 2 + Metrics.hintOffsetX,
                          y: proxy.size.height / 2 + Metrics.hintOffsetY + Metrics.bubbleHeight)
        }
        .ignoresSafeArea()
    }

    private static var foregroundWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
    }
}
