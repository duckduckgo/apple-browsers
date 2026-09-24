//
//  UnifiedToggleInputCardModeCue.swift
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

import UIKit

/// Owns the Duck.ai cues drawn around the input — the glowing border, the border sweep and the
/// keyboard edge glow — and lays them over the host's card. Each shows for as long as the card is
/// open in Duck.ai.
@MainActor
final class UnifiedToggleInputCardModeCue {

    private enum Metrics {
        /// As thin as the typing border; launches fast and eases off as it fades, so it feels thrown.
        static let sweepStyle = UnifiedToggleInputModeCueSweepView.Style(
            lineWidth: 1.5,
            glowRadius: 4,
            secondsPerLap: 0.75,
            laps: 1.5,
            timing: CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1),
            headGlowRadius: 8,
            afterglowOpacity: 0.3
        )
        /// Cues bloom in gently rather than snapping on with the first keystroke.
        static let fadeInDuration: TimeInterval = 0.6
        static let fadeOutDuration: TimeInterval = 0.35
    }

    private let settings: UnifiedToggleInputModeCueSettings
    private let isReduceMotionEnabled: () -> Bool
    private let borderView = UnifiedToggleInputModeBorderView()
    private var sweepView: UnifiedToggleInputModeCueSweepView?
    private weak var host: UIView?
    private let keyboardEdgeView = UnifiedToggleInputKeyboardEdgeGlowView()
    private var areCuesShown = false
    private weak var card: UIView?

    init(settings: UnifiedToggleInputModeCueSettings = UnifiedToggleInputModeCueSettings(),
         isReduceMotionEnabled: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled }) {
        self.settings = settings
        self.isReduceMotionEnabled = isReduceMotionEnabled
    }

    /// Call once `card` is in `host`.
    func install(in host: UIView, card: UIView) {
        self.host = host
        self.card = card
        host.insertSubview(borderView, aboveSubview: card)
        pin(borderView, to: card)
    }

    /// The keyboard edge needs a host spanning the screen: a view's keyboard guide never reaches
    /// past its own bounds, so the input's own view would pin the glow to the card instead.
    func installKeyboardEdge(in screenHost: UIView) {
        keyboardEdgeView.install(in: screenHost)
    }

    /// Call from the host's `layoutSubviews`, which runs inside its animations, so the cues follow the
    /// card's corners as it morphs.
    func syncGeometry() {
        guard let card else { return }
        borderView.cornerRadius = card.layer.cornerRadius
    }

    /// Fades the cues in or out on their own timing.
    /// - Parameter isActive: `true` while the card is expanded with its toggle; the collapsed pill stays
    ///   the plain omnibar.
    func update(mode: TextEntryMode, isActive: Bool) {
        let style = settings.style
        let isShowingDuckAI = isActive && mode == .aiChat
        let showsBorder = isShowingDuckAI && style.showsGlowingBorder
        let showsKeyboardEdge = isShowingDuckAI && style.showsKeyboardEdgeGlow
        let showsAnyCue = showsBorder || showsKeyboardEdge

        let duration = showsAnyCue && !areCuesShown ? Metrics.fadeInDuration : Metrics.fadeOutDuration
        areCuesShown = showsAnyCue
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.borderView.apply(mode: mode, isVisible: showsBorder)
            self.keyboardEdgeView.apply(mode: mode, isVisible: showsKeyboardEdge)
        }
        if !isActive {
            removeSweepView()
        }
    }

    /// Sends one comet one and a half times around the card's border, then fades it out. Duck.ai only,
    /// so the sweep itself says which mode the card is in.
    func playSweep(mode: TextEntryMode) {
        guard settings.style == .borderSweep, mode == .aiChat, let sweepView = installSweepView() else { return }
        sweepView.play(gradient: UnifiedToggleInputModeCuePalette.gradient(for: mode),
                       travels: !isReduceMotionEnabled()) { [weak self, weak sweepView] in
            guard let sweepView, sweepView === self?.sweepView else { return }
            self?.removeSweepView()
        }
    }

    private func installSweepView() -> UnifiedToggleInputModeCueSweepView? {
        guard let host, let card else { return nil }
        removeSweepView()
        let sweepView = UnifiedToggleInputModeCueSweepView(cornerRadius: card.layer.cornerRadius,
                                                           style: Metrics.sweepStyle)
        host.insertSubview(sweepView, aboveSubview: borderView)
        pin(sweepView, to: card)
        self.sweepView = sweepView
        return sweepView
    }

    private func removeSweepView() {
        sweepView?.removeFromSuperview()
        sweepView = nil
    }

    private func pin(_ view: UIView, to card: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            view.topAnchor.constraint(equalTo: card.topAnchor),
            view.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
    }
}

private extension UnifiedToggleInputModeCueStyle {

    var showsGlowingBorder: Bool {
        switch self {
        case .glowingBorder, .glowingBorderAndKeyboardEdge: true
        case .off, .textShimmer, .borderSweep, .keyboardEdgeGlow: false
        }
    }

    var showsKeyboardEdgeGlow: Bool {
        switch self {
        case .keyboardEdgeGlow, .glowingBorderAndKeyboardEdge: true
        case .off, .textShimmer, .glowingBorder, .borderSweep: false
        }
    }
}
