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

/// What the browser chrome around the tab knows that the swipe gates on.
struct DuckAISwipeNewChatChromeState {
    let isGenerating: Bool
    let isVoiceSessionActive: Bool
    let isInputHidden: Bool
    /// Top of the bottom chrome (the Duck.ai input bar), in window coordinates; nil when none is showing.
    let bottomChromeMinY: CGFloat?
}

/// Duck.ai scrolls an inner container, not the web view's scroll view, so the native scroll view never
/// reports overscroll. Instead a simultaneous pan asks the page, as it begins, whether the chat under the
/// finger is at its bottom, and if so measures how far the finger pulls up from there.
@MainActor
final class DuckAISwipeNewChatHandler: NSObject, UIGestureRecognizerDelegate {

    private weak var webView: WKWebView?
    private weak var hostView: UIView?
    private let isFeatureEnabled: () -> Bool
    private let chromeState: () -> DuckAISwipeNewChatChromeState?
    private let onStartNewChat: () -> Void

    private let pan = UIPanGestureRecognizer()
    private let tickHaptic = UIImpactFeedbackGenerator(style: .light)
    private let armHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let indicator: DuckAISwipeNewChatIndicatorView
    private var indicatorBottomConstraint: NSLayoutConstraint?
    private let backdrop = UIView()

    private var pull = DuckAISwipeNewChat.Pull.idle
    /// Where the current pan started, to re-check eligibility as the chrome changes during the pull.
    private var panStart: (velocity: CGPoint, y: CGFloat, bottomInsetMinY: CGFloat)?
    /// Bumped by each touch-down, by `cancel()` and by navigation mid-pull, so late page replies and animation
    /// completions from an earlier interaction do nothing.
    private var generation = 0
    /// Where the latest finger went down on the web view, for the page's at-bottom check.
    private var touchDownPoint: CGPoint?
    private var commitState = DuckAISwipeNewChat.Commit.idle

    private var movesContent: Bool { !UIAccessibility.isReduceMotionEnabled }

    init(webView: WKWebView,
         hostView: UIView,
         isFireTab: Bool,
         isFeatureEnabled: @escaping () -> Bool,
         chromeState: @escaping () -> DuckAISwipeNewChatChromeState?,
         onStartNewChat: @escaping () -> Void) {
        self.webView = webView
        self.hostView = hostView
        self.isFeatureEnabled = isFeatureEnabled
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
    /// With nothing in progress it leaves the web view alone.
    func cancel() {
        guard pull.isUnderway || commitState != .idle || !backdrop.isHidden else { return }
        pull = .idle
        panStart = nil
        commitState = .idle
        restore()
    }

    /// A pull belongs to the chat it started on, so navigating away mid-pull drops it and any page reply still due.
    func webViewURLDidChange() {
        if pull.isUnderway {
            generation += 1
            apply(pull.handle(.cancelled))
        }
        apply(commitState.handle(.urlChanged(chatID: webView?.url?.duckAIChatID)))
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
        let eligibility = DuckAISwipeNewChat.Eligibility(isFeatureEnabled: isFeatureEnabled(),
                                                         isPhone: UIDevice.current.userInterfaceIdiom == .phone,
                                                         hasChat: webView?.url?.duckAIChatID != nil,
                                                         isGenerating: chrome.isGenerating,
                                                         isVoiceSessionActive: chrome.isVoiceSessionActive,
                                                         isInputHidden: chrome.isInputHidden,
                                                         panVelocity: panStart.velocity,
                                                         startY: panStart.y,
                                                         bottomInsetMinY: panStart.bottomInsetMinY)
        return (eligibility, chrome)
    }

    private func isStillEligible() -> Bool {
        eligibility()?.eligibility.isEligible == true
    }

    private func beginIfEligible(_ gesture: UIPanGestureRecognizer, in hostView: UIView) -> Bool {
        guard let window = hostView.window else { return false }
        let homeIndicatorTop = window.bounds.maxY - window.safeAreaInsets.bottom
        panStart = (gesture.velocity(in: hostView),
                    gesture.location(in: hostView).y,
                    hostView.convert(CGPoint(x: 0, y: homeIndicatorTop), from: nil).y)
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
                apply(commitState.handle(.released(chatID: webView?.url?.duckAIChatID)))
            }
        }
    }

    private func apply(_ effects: [DuckAISwipeNewChat.Commit.Effect]) {
        for effect in effects {
            switch effect {
            case .fadeOut:
                fadeOut()
            case .requestNewChat:
                webView?.transform = .identity
                indicator.transform = .identity
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

    /// The chat follows the finger up to the trigger, then resists; the indicator rises at a fraction of that.
    private func followPull(distance: CGFloat, progress: CGFloat, isArmed: Bool) {
        let constants = DuckAISwipeNewChat.Constants.self
        let offset = min(distance, constants.triggerDistance)
            + max(distance - constants.triggerDistance, 0) * constants.overpullResistance
        indicator.update(progress: progress, isArmed: isArmed)
        guard movesContent else { return }
        if backdrop.isHidden {
            showBackdrop()
        }
        webView?.transform = CGAffineTransform(translationX: 0, y: -offset)
        indicator.transform = CGAffineTransform(translationX: 0, y: -offset * constants.indicatorFollow)
    }

    private func springBack() {
        let generation = generation
        UIView.animate(withDuration: DuckAISwipeNewChat.Constants.springBackDuration, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.webView?.transform = .identity
            self.indicator.transform = .identity
            self.indicator.alpha = 0
        } completion: { _ in
            guard generation == self.generation else { return }
            self.hideBackdrop()
        }
    }

    /// The old chat carries on up and fades out before the new tab is asked for.
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
            self.apply(self.commitState.handle(.fadedOut(chatID: self.webView?.url?.duckAIChatID,
                                                         isEligible: self.isStillEligible())))
        }
    }

    /// Puts the chat back in place at once, and makes any animation or reply still in flight do nothing.
    private func restore() {
        generation += 1
        webView?.transform = .identity
        webView?.alpha = 1
        indicator.transform = .identity
        indicator.alpha = 0
        indicator.reset()
        hideBackdrop()
    }

    /// The bottom chrome doesn't move during a pull, so the indicator is placed once per pan.
    private func placeIndicator(in hostView: UIView, above chromeMinYInWindow: CGFloat) {
        if indicator.superview !== hostView {
            indicator.removeFromSuperview()
            hostView.addSubview(indicator)
            let bottom = indicator.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
            NSLayoutConstraint.activate([indicator.centerXAnchor.constraint(equalTo: hostView.centerXAnchor), bottom])
            indicatorBottomConstraint = bottom
        }
        hostView.bringSubviewToFront(indicator)
        let chromeTop = min(hostView.convert(CGPoint(x: 0, y: chromeMinYInWindow), from: nil).y, hostView.bounds.maxY)
        indicatorBottomConstraint?.constant = chromeTop - hostView.bounds.maxY - DuckAISwipeNewChat.Constants.indicatorSpacing
    }

    private func checkAtBottom() {
        guard let webView, webView.bounds.width > 0, webView.bounds.height > 0 else { return }
        let generation = generation
        let point = touchDownPoint ?? pan.location(in: webView)
        let fraction = CGPoint(x: point.x / webView.bounds.width, y: point.y / webView.bounds.height)
        webView.evaluateJavaScript(Self.atBottomScript(atFractionOfViewport: fraction)) { [weak self] result, _ in
            guard let self, generation == self.generation, let hostView = self.hostView else { return }
            self.apply(self.pull.handle(.pageAnswered(isAtBottom: result as? Bool == true,
                                                      translation: self.pan.translation(in: hostView).y)))
        }
    }

    /// Whether the chat under the finger is at its bottom. The finger is given as a fraction of the web view, which
    /// the page scales to its own viewport, so text zoom doesn't shift it. The chat is the nearest vertical
    /// scroller between half the viewport and the viewport tall: a code block or menu under the finger is shorter,
    /// and a content wrapper styled as a scroller but taller than the viewport never scrolls. A chat too short to
    /// scroll is already at its bottom. Anything else, including no element at all, is not.
    private static func atBottomScript(atFractionOfViewport fraction: CGPoint) -> String {
        """
        (function(fx, fy) {
          const hit = document.elementFromPoint(fx * innerWidth, fy * innerHeight);
          for (let el = hit; el && el !== document.documentElement; el = el.parentElement) {
            if (/(auto|scroll)/.test(getComputedStyle(el).overflowY)
                && el.clientHeight >= innerHeight / 2 && el.clientHeight <= innerHeight) {
              return el.scrollTop + el.clientHeight >= el.scrollHeight - 4;
            }
          }
          return false;
        })(\(fraction.x), \(fraction.y))
        """
    }

    /// The chat uncovers what is behind the web view as it slides up and fades; this fills that with the Duck.ai
    /// page's own colour token. It doesn't read the web view's background colours, which the chrome, site
    /// theming and pull-to-refresh each overwrite. It is the handler's own view, so no shared background changes.
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

    /// The first finger down asks the page about the chat under it straight away, before the chat scrolls with the
    /// finger; by the time the pan begins it has already moved. Never mid-commit, so the fade and timeout stay valid.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard pan.numberOfTouches == 0, isFeatureEnabled(), commitState == .idle, let webView else { return true }
        generation += 1
        touchDownPoint = touch.location(in: webView)
        apply(pull.handle(.touchedDown))
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        isFeatureEnabled() && commitState == .idle
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// A ring that fills as the pull nears the trigger, then becomes a button styled like the Duck.ai input's send button.
private final class DuckAISwipeNewChatIndicatorView: UIView {

    private enum Metrics {
        static let diameter: CGFloat = 32
        static let lineWidth: CGFloat = 2.5
        static let labelSpacing: CGFloat = 6
        /// The fraction of the pull over which the indicator fades in.
        static let fadeInProgress: CGFloat = 0.3
        static let collapsed = CGAffineTransform(scaleX: 0.01, y: 0.01)
    }

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
        button.setIcon(DesignSystemImages.Glyphs.Size16.compose)
        button.applySubmitStyle(isActive: true, isFireTab: isFireTab, activeForeground: .white)
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

    /// The ring takes the button's own colour, so the two always match.
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

    /// Under Reduce Motion the button fades in place; otherwise it grows out of the ring.
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
