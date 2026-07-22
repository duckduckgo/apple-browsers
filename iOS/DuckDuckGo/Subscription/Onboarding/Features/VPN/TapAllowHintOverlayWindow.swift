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

/// Presents the "Tap allow" pointer in a dedicated `UIWindow` at `.alert + 1` so it renders **above** the
/// system VPN-configuration permission alert — an in-app overlay would sit behind it. The window is
/// non-interactive, so taps pass straight through to the real "Allow" button beneath. Held by the view for
/// its lifetime; ``show()`` / ``hide()`` bracket the first-time turn-on.
@MainActor
final class TapAllowHintOverlayWindow {
    private enum Metrics {
        // `FloatingPointerBubble` geometry (see FloatingPointerBubble.swift): a 33pt arrow sits above the pill,
        // and the pill is the 17pt "Tap allow" label plus 12pt vertical padding top & bottom (~44pt).
        static let bubbleArrowHeight: CGFloat = 33
        static let bubblePillHeight: CGFloat = 44
        static let bubbleHeight: CGFloat = bubbleArrowHeight + bubblePillHeight

        // Screen-centre-relative target for the arrow *tip* (the dialog is centred): its left "Allow" button.
        // No API exposes the dialog's layout, so these are hand-tuned; `hintView` factors in the bubble height
        // so the tip — not the bubble centre — lands here. iOS 26's Liquid Glass alert is wider, more padded,
        // and left-aligned, so it gets its own offsets from the iOS 18-era layout.
        static var hintOffsetX: CGFloat {
            return -77
        }
        static var hintOffsetY: CGFloat {
            if #available(iOS 26, *) { return 143 }
            return 125
        }
    }

    private var window: UIWindow?

    /// Layers the hint over the frontmost scene. No-op if already shown or no foreground scene is found.
    func show() {
        guard window == nil, let scene = Self.foregroundWindowScene else { return }
        let hostingController = UIHostingController(rootView: Self.hintView)
        hostingController.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.isUserInteractionEnabled = false
        window.rootViewController = hostingController
        window.isHidden = false
        self.window = window
        // The window is non-interactive (VoiceOver can't reach it), so announce the hint for VO users.
        UIAccessibility.post(notification: .announcement,
                             argument: UserText.subscriptionOnboardingVPNActivationTapAllowHint)
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }

    // The system dialog is screen-centered, so position from the live screen centre (the window-sized
    // `GeometryReader`) — device-adaptive without a per-model size table. `.position` centres the bubble, so
    // add half its height on the y axis so the arrow *tip* (its top), not the centre, lands on the target.
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
