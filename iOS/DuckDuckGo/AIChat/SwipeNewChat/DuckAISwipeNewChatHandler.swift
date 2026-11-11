//
//  DuckAISwipeNewChatHandler.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit
import WebKit

struct DuckAISwipeNewChatChromeState {
    let isGenerating: Bool
    let isVoiceSessionActive: Bool
    let isInputHidden: Bool
    /// Top of the Duck.ai input bar in window coordinates; nil when it isn't showing.
    let bottomChromeMinY: CGFloat?
}

/// Duck.ai scrolls an inner element, so the web view never reports overscroll. A simultaneous pan asks the page
/// whether the chat is at its bottom, then measures the pull from there.
@MainActor
final class DuckAISwipeNewChatHandler: NSObject, UIGestureRecognizerDelegate {

    private weak var webView: WKWebView?
    private weak var hostView: UIView?
    private let feature: DuckAISwipeNewChatFeatureProviding
    private let chromeState: () -> DuckAISwipeNewChatChromeState?
    private let onStartNewChat: () -> Void

    private let pan = UIPanGestureRecognizer()
    private let tickHaptic = UIImpactFeedbackGenerator(style: .light)
    private let armHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let indicator: DuckAISwipeNewChatIndicatorView
    private let indicatorSlot = UIView()
    private var indicatorSlotBottomY: CGFloat = 0
    private let backdrop = UIView()

    private var pull = DuckAISwipeNewChat.Pull.idle
    private var panStart: (velocity: CGPoint, y: CGFloat, bottomInsetMinY: CGFloat, isHeld: Bool)?
    private var touchDownTime: TimeInterval?
    /// Bumped to make late page replies and animation completions from an earlier interaction do nothing.
    private var generation = 0
    private var commitState = DuckAISwipeNewChat.Commit.idle

    private var movesContent: Bool { !UIAccessibility.isReduceMotionEnabled }

    private var chatID: String? {
        guard let url = webView?.url else { return nil }
        return url.duckAIChatID ?? url.duckAISharedChatID
    }

    /// A selection being dragged isn't a pull.
    private static let canPullExpression = "(getSelection()?.isCollapsed ?? true) && \(DuckAIChatScroller.isAtBottomExpression)"

    init(webView: WKWebView,
         hostView: UIView,
         isFireTab: Bool,
         feature: DuckAISwipeNewChatFeatureProviding,
         chromeState: @escaping () -> DuckAISwipeNewChatChromeState?,
         onStartNewChat: @escaping () -> Void) {
        self.webView = webView
        self.hostView = hostView
        self.feature = feature
        self.chromeState = chromeState
        self.onStartNewChat = onStartNewChat
        indicator = DuckAISwipeNewChatIndicatorView(isFireTab: isFireTab)
        super.init()
        backdrop.isHidden = true
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        pan.delaysTouchesEnded = false
        webView.addGestureRecognizer(pan)
    }

    /// Puts the chat back as it was, mid-pull or mid-commit; for when the tab goes off screen.
    func cancel() {
        guard pull.isUnderway || commitState != .idle || !backdrop.isHidden else { return }
        pull = .idle
        panStart = nil
        commitState = .idle
        restore()
    }

    /// Drops any pull or page reply that belongs to the previous chat.
    func webViewURLDidChange() {
        if pull != .idle {
            generation += 1
            apply(pull.handle(.cancelled))
        }
        apply(commitState.handle(.urlChanged(chatID: chatID)))
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let hostView else { return }
        let event: DuckAISwipeNewChat.Event
        switch gesture.state {
        case .began:
            event = .began(isEligible: beginIfEligible(gesture, in: hostView), translation: gesture.translation(in: hostView).y)
        case .changed:
            event = pull == .idle || isStillEligible() ? .moved(translation: gesture.translation(in: hostView).y) : .cancelled
        case .ended:
            event = pull == .idle || isStillEligible() ? .ended : .cancelled
        case .cancelled, .failed:
            event = .cancelled
        default:
            return
        }
        apply(pull.handle(event))
    }

    private func eligibility() -> (eligibility: DuckAISwipeNewChat.Eligibility, chrome: DuckAISwipeNewChatChromeState)? {
        guard let panStart, let chrome = chromeState() else { return nil }
        let eligibility = DuckAISwipeNewChat.Eligibility(isFeatureAvailable: feature.isAvailable,
                                                         hasChat: chatID != nil,
                                                         isGenerating: chrome.isGenerating,
                                                         isVoiceSessionActive: chrome.isVoiceSessionActive,
                                                         isInputHidden: chrome.isInputHidden,
                                                         panVelocity: panStart.velocity,
                                                         startY: panStart.y,
                                                         bottomInsetMinY: panStart.bottomInsetMinY,
                                                         isHeld: panStart.isHeld)
        return (eligibility, chrome)
    }

    private func isStillEligible() -> Bool {
        eligibility()?.eligibility.isEligible == true
    }

    private func beginIfEligible(_ gesture: UIPanGestureRecognizer, in hostView: UIView) -> Bool {
        guard let window = hostView.window else { return false }
        let homeIndicatorTop = window.bounds.maxY - window.safeAreaInsets.bottom
        let heldFor = touchDownTime.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
        panStart = (gesture.velocity(in: hostView),
                    gesture.location(in: hostView).y,
                    hostView.convert(CGPoint(x: 0, y: homeIndicatorTop), from: nil).y,
                    heldFor >= DuckAISwipeNewChat.Constants.longPressDuration)
        guard let current = eligibility(), current.eligibility.isEligible else { return false }
        tickHaptic.prepare()
        armHaptic.prepare()
        indicator.reset()
        placeIndicator(in: hostView, above: current.chrome.bottomChromeMinY ?? homeIndicatorTop)
        return true
    }

    private func apply(_ effects: [DuckAISwipeNewChat.Effect]) {
        for effect in effects {
            switch effect {
            case .checkAtBottom:
                checkAtBottom()
            case .pull(let distance, let progress, let isArmed):
                followPull(distance: distance, progress: progress, isArmed: isArmed)
            case .tick(let step):
                let intensity = 0.4 + 0.5 * CGFloat(step) / CGFloat(DuckAISwipeNewChat.Constants.hapticSteps)
                tickHaptic.impactOccurred(intensity: intensity)
                tickHaptic.prepare()
            case .arm:
                armHaptic.impactOccurred()
                armHaptic.prepare()
            case .springBack:
                springBack()
            case .startNewChat:
                apply(commitState.handle(.released(chatID: chatID)))
            }
        }
    }

    private func apply(_ effects: [DuckAISwipeNewChat.Commit.Effect]) {
        for effect in effects {
            switch effect {
            case .fadeOut:
                fadeOut()
            case .requestNewChat:
                // Opening the tab snapshots this one, so the chat is put back first.
                webView?.transform = .identity
                webView?.alpha = 1
                setIndicatorSlotHeight(0)
                indicator.reset()
                onStartNewChat()
            case .scheduleTimeout:
                let generation = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + DuckAISwipeNewChat.Constants.newTabTimeout) { [weak self] in
                    guard let self, generation == self.generation else { return }
                    self.apply(self.commitState.handle(.timedOut))
                }
            case .restore:
                restore()
            }
        }
    }

    private func followPull(distance: CGFloat, progress: CGFloat, isArmed: Bool) {
        let constants = DuckAISwipeNewChat.Constants.self
        let offset = min(distance, constants.triggerDistance)
            + max(distance - constants.triggerDistance, 0) * constants.overpullResistance
        guard movesContent else {
            indicator.update(progress: progress, isArmed: isArmed)
            setIndicatorSlotHeight(constants.triggerDistance)
            return
        }
        let revealed = constants.indicatorSpacing + DuckAISwipeNewChatIndicatorView.circleDiameter
        indicator.update(progress: max(0, min((offset - revealed) / (constants.triggerDistance - revealed), 1)), isArmed: isArmed)
        if backdrop.isHidden {
            showBackdrop()
        }
        webView?.transform = CGAffineTransform(translationX: 0, y: -offset)
        setIndicatorSlotHeight(offset)
    }

    private func springBack() {
        let generation = generation
        UIView.animate(withDuration: DuckAISwipeNewChat.Constants.springBackDuration, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.webView?.transform = .identity
            self.setIndicatorSlotHeight(0)
            self.indicator.alpha = 0
        } completion: { _ in
            guard generation == self.generation else { return }
            self.hideBackdrop()
        }
    }

    private func fadeOut() {
        let constants = DuckAISwipeNewChat.Constants.self
        let generation = generation
        UIView.animate(withDuration: constants.commitDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            if self.movesContent, let webView = self.webView {
                webView.transform = webView.transform.translatedBy(x: 0, y: -constants.triggerDistance)
            }
            self.webView?.alpha = 0
            self.indicator.alpha = 0
        } completion: { _ in
            guard generation == self.generation else { return }
            self.apply(self.commitState.handle(.fadedOut(chatID: self.chatID,
                                                         isEligible: self.isStillEligible())))
        }
    }

    private func restore() {
        generation += 1
        webView?.transform = .identity
        webView?.alpha = 1
        setIndicatorSlotHeight(0)
        indicator.alpha = 0
        indicator.reset()
        hideBackdrop()
    }

    private func placeIndicator(in hostView: UIView, above chromeMinYInWindow: CGFloat) {
        if indicatorSlot.superview !== hostView {
            indicatorSlot.removeFromSuperview()
            indicatorSlot.isUserInteractionEnabled = false
            indicatorSlot.clipsToBounds = true
            if indicator.superview !== indicatorSlot {
                indicatorSlot.addSubview(indicator)
                let centered = indicator.centerYAnchor.constraint(equalTo: indicatorSlot.centerYAnchor)
                centered.priority = .defaultHigh
                NSLayoutConstraint.activate([
                    centered,
                    indicator.centerXAnchor.constraint(equalTo: indicatorSlot.centerXAnchor),
                    indicator.topAnchor.constraint(greaterThanOrEqualTo: indicatorSlot.topAnchor,
                                                   constant: DuckAISwipeNewChat.Constants.indicatorSpacing),
                ])
            }
            hostView.addSubview(indicatorSlot)
        }
        hostView.bringSubviewToFront(indicatorSlot)
        indicatorSlotBottomY = min(hostView.convert(CGPoint(x: 0, y: chromeMinYInWindow), from: nil).y, hostView.bounds.maxY)
        setIndicatorSlotHeight(0)
    }

    private func setIndicatorSlotHeight(_ height: CGFloat) {
        guard let hostView = indicatorSlot.superview else { return }
        indicatorSlot.frame = CGRect(x: 0, y: indicatorSlotBottomY - height, width: hostView.bounds.width, height: height)
        indicatorSlot.layoutIfNeeded()
    }

    private func checkAtBottom() {
        guard let webView, webView.bounds.width > 0, webView.bounds.height > 0 else { return }
        let generation = generation
        webView.evaluateJavaScript(Self.canPullExpression) { [weak self] result, _ in
            guard let self, generation == self.generation, let hostView = self.hostView else { return }
            self.apply(self.pull.handle(.pageAnswered(isAtBottom: result as? Bool == true,
                                                      translation: self.pan.translation(in: hostView).y)))
        }
    }

    /// Uses the page's colour token: the web view's own background colours are overwritten by other chrome.
    private func showBackdrop() {
        guard let webView, let container = webView.superview else { return }
        if backdrop.superview !== container {
            backdrop.removeFromSuperview()
            backdrop.translatesAutoresizingMaskIntoConstraints = false
            backdrop.isUserInteractionEnabled = false
            container.insertSubview(backdrop, belowSubview: webView)
            NSLayoutConstraint.activate([
                backdrop.topAnchor.constraint(equalTo: webView.topAnchor),
                backdrop.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
                backdrop.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            ])
        }
        container.insertSubview(backdrop, belowSubview: webView)
        backdrop.backgroundColor = UIColor(singleUseColor: .duckAIWebViewBackground)
        backdrop.isHidden = false
    }

    private func hideBackdrop() {
        backdrop.isHidden = true
    }

    /// Asks the page at touch-down, before the chat scrolls with the finger.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard pan.numberOfTouches == 0, feature.isAvailable, commitState == .idle,
              chatID != nil else { return true }
        generation += 1
        touchDownTime = touch.timestamp
        apply(pull.handle(.touchedDown))
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        feature.isAvailable && commitState == .idle && chatID != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// A ring that fills as the pull nears the trigger, then becomes a button styled like the input's send button.
private final class DuckAISwipeNewChatIndicatorView: UIView {

    private enum Metrics {
        static let diameter: CGFloat = 48
        static let lineWidth: CGFloat = 2.5
        static let labelSpacing: CGFloat = 6
        static let fadeInProgress: CGFloat = 0.3
        static let collapsed = CGAffineTransform(scaleX: 0.01, y: 0.01)
    }

    static var circleDiameter: CGFloat { Metrics.diameter }

    private let circle = UIView()
    private let ring = CAShapeLayer()
    private let button = CircularButton()
    private let label = UILabel()
    private var isArmed = false

    init(isFireTab: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        alpha = 0

        circle.translatesAutoresizingMaskIntoConstraints = false
        ring.fillColor = UIColor.clear.cgColor
        ring.lineWidth = Metrics.lineWidth
        ring.lineCap = .round
        ring.strokeEnd = 0
        circle.layer.addSublayer(ring)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.isShadowHidden = true
        button.setIcon(DesignSystemImages.Glyphs.Size24.compose)
        button.applySubmitStyle(isActive: true, isFireTab: isFireTab,
                                activeForeground: isFireTab ? .white : UIColor(designSystemColor: .accentContentPrimary))
        circle.addSubview(button)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .daxCaption()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textSecondary)
        label.text = UserText.actionNewAIChat

        addSubview(circle)
        addSubview(label)
        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: topAnchor),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.widthAnchor.constraint(equalToConstant: Metrics.diameter),
            circle.heightAnchor.constraint(equalToConstant: Metrics.diameter),
            button.topAnchor.constraint(equalTo: circle.topAnchor),
            button.bottomAnchor.constraint(equalTo: circle.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: circle.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: circle.trailingAnchor),
            label.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: Metrics.labelSpacing),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        reset()
        applyRingColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = (Metrics.diameter - Metrics.lineWidth) / 2
        let center = CGPoint(x: Metrics.diameter / 2, y: Metrics.diameter / 2)
        ring.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyRingColor()
        }
    }

    private func applyRingColor() {
        ring.strokeColor = button.backgroundColor?.resolvedColor(with: traitCollection).cgColor
    }

    func reset() {
        isArmed = false
        showButton(false)
        ring.strokeEnd = 0
    }

    func update(progress: CGFloat, isArmed: Bool) {
        layer.removeAllAnimations()
        alpha = min(progress / Metrics.fadeInProgress, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = progress
        CATransaction.commit()

        guard isArmed != self.isArmed else { return }
        self.isArmed = isArmed
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.15) { self.showButton(isArmed) }
        } else {
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.showButton(isArmed)
            }
        }
    }

    private func showButton(_ isShown: Bool) {
        if UIAccessibility.isReduceMotionEnabled {
            button.transform = .identity
            button.alpha = isShown ? 1 : 0
        } else {
            button.alpha = 1
            button.transform = isShown ? .identity : Metrics.collapsed
        }
    }
}
