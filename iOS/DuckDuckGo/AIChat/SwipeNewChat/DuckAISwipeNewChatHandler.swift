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
import UIKit.UIGestureRecognizerSubclass
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

    private let pan = TouchDownPanGestureRecognizer()
    private let tickHaptic = UIImpactFeedbackGenerator(style: .light)
    private let armHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let indicator: DuckAISwipeNewChatIndicatorView
    private let indicatorSlot = UIView()
    private var indicatorSlotBottomY: CGFloat = 0
    private let backdrop = UIView()

    private var pull = DuckAISwipeNewChat.Pull.idle
    private var panStart: (velocity: CGPoint, y: CGFloat, bottomInsetMinY: CGFloat, isHeld: Bool)?
    private var touchDownTime: TimeInterval?
    /// Bumped to make late page replies from an earlier touch do nothing.
    private var pageQuery = 0
    /// Bumped to make completions of animations that something newer has taken over do nothing.
    private var animation = 0
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
        backdrop.isUserInteractionEnabled = false
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        buildIndicator(in: hostView)
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.onFirstTouchDown = { [weak self] touch in self?.touchedDown(touch) }
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
            pageQuery += 1
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
                onStartNewChat()
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
        animation += 1
        let revealed = constants.indicatorSpacing + DuckAISwipeNewChatIndicatorView.circleDiameter
        indicator.update(progress: max(0, min((offset - revealed) / (constants.triggerDistance - revealed), 1)), isArmed: isArmed)
        if backdrop.isHidden {
            showBackdrop()
        }
        webView?.transform = CGAffineTransform(translationX: 0, y: -offset)
        setIndicatorSlotHeight(offset)
    }

    private func springBack() {
        let animation = animation
        UIView.animate(withDuration: DuckAISwipeNewChat.Constants.springBackDuration, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.webView?.transform = .identity
            self.setIndicatorSlotHeight(0)
            self.indicator.alpha = 0
        } completion: { _ in
            guard animation == self.animation else { return }
            self.hideBackdrop()
        }
    }

    private func fadeOut() {
        let constants = DuckAISwipeNewChat.Constants.self
        let animation = animation
        UIView.animate(withDuration: constants.commitDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            if self.movesContent, let webView = self.webView {
                webView.transform = webView.transform.translatedBy(x: 0, y: -constants.triggerDistance)
            }
            self.webView?.alpha = 0
            self.indicator.alpha = 0
        } completion: { _ in
            guard animation == self.animation else { return }
            self.apply(self.commitState.handle(.fadedOut(chatID: self.chatID,
                                                         isEligible: self.isStillEligible())))
        }
    }

    private func restore() {
        pageQuery += 1
        animation += 1
        webView?.transform = .identity
        webView?.alpha = 1
        setIndicatorSlotHeight(0)
        indicator.alpha = 0
        indicator.reset()
        hideBackdrop()
    }

    private func buildIndicator(in hostView: UIView) {
        indicatorSlot.isUserInteractionEnabled = false
        indicatorSlot.clipsToBounds = true
        indicatorSlot.addSubview(indicator)
        let centered = indicator.centerYAnchor.constraint(equalTo: indicatorSlot.centerYAnchor)
        centered.priority = .defaultHigh
        NSLayoutConstraint.activate([
            centered,
            indicator.centerXAnchor.constraint(equalTo: indicatorSlot.centerXAnchor),
            indicator.topAnchor.constraint(greaterThanOrEqualTo: indicatorSlot.topAnchor,
                                           constant: DuckAISwipeNewChat.Constants.indicatorSpacing),
        ])
        hostView.addSubview(indicatorSlot)
    }

    private func placeIndicator(in hostView: UIView, above chromeMinYInWindow: CGFloat) {
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
        let pageQuery = pageQuery
        webView.evaluateJavaScript(Self.canPullExpression) { [weak self] result, _ in
            guard let self, pageQuery == self.pageQuery, let hostView = self.hostView else { return }
            self.apply(self.pull.handle(.pageAnswered(isAtBottom: result as? Bool == true,
                                                      translation: self.pan.translation(in: hostView).y)))
        }
    }

    /// Uses the page's colour token: the web view's own background colours are overwritten by other chrome.
    private func showBackdrop() {
        guard let webView, let container = webView.superview else { return }
        if backdrop.superview !== container {
            backdrop.removeFromSuperview()
            container.insertSubview(backdrop, belowSubview: webView)
            NSLayoutConstraint.activate([
                backdrop.topAnchor.constraint(equalTo: webView.topAnchor),
                backdrop.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
                backdrop.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            ])
        }
        backdrop.backgroundColor = UIColor(singleUseColor: .duckAIWebViewBackground)
        backdrop.isHidden = false
    }

    private func hideBackdrop() {
        backdrop.isHidden = true
    }

    /// Asks the page at touch-down, before the chat scrolls with the finger.
    private func touchedDown(_ touch: UITouch) {
        guard feature.isAvailable, commitState == .idle, chatID != nil else { return }
        pageQuery += 1
        touchDownTime = touch.timestamp
        apply(pull.handle(.touchedDown))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        feature.isAvailable && commitState == .idle && chatID != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Reports the first finger landing, before the pan decides anything.
private final class TouchDownPanGestureRecognizer: UIPanGestureRecognizer {

    var onFirstTouchDown: ((UITouch) -> Void)?
    private var isTouched = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if !isTouched, let touch = touches.first {
            isTouched = true
            onFirstTouchDown?(touch)
        }
        super.touchesBegan(touches, with: event)
    }

    override func reset() {
        super.reset()
        isTouched = false
    }
}
