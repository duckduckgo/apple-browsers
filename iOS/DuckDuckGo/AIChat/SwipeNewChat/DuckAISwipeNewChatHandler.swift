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
    let isKeyboardVisible: Bool
    let isGenerating: Bool
    /// Top of the bottom chrome (the Duck.ai input bar), in window coordinates; nil when none is showing.
    let bottomChromeMinY: CGFloat?
}

/// Duck.ai scrolls an inner container, not the web view's scroll view, so the native scroll view never
/// reports overscroll. Instead a simultaneous pan asks the page whether the container under the finger is
/// at its bottom, then measures how far the finger keeps pulling up from there.
@MainActor
final class DuckAISwipeNewChatHandler: NSObject, UIGestureRecognizerDelegate {

    private weak var webView: WKWebView?
    private weak var hostView: UIView?
    private let isFeatureEnabled: () -> Bool
    private let chromeState: () -> DuckAISwipeNewChatChromeState?
    private let onStartNewChat: () -> Void

    private let pan = UIPanGestureRecognizer()
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private lazy var hint = DuckAISwipeNewChatHintView()
    private var hintBottomConstraint: NSLayoutConstraint?

    private var pull = DuckAISwipeNewChat.Pull.idle
    private var panID = 0
    private var isCheckInFlight = false

    init(webView: WKWebView,
         hostView: UIView,
         isFeatureEnabled: @escaping () -> Bool,
         chromeState: @escaping () -> DuckAISwipeNewChatChromeState?,
         onStartNewChat: @escaping () -> Void) {
        self.webView = webView
        self.hostView = hostView
        self.isFeatureEnabled = isFeatureEnabled
        self.chromeState = chromeState
        self.onStartNewChat = onStartNewChat
        super.init()
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        pan.delaysTouchesEnded = false
        webView.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let hostView else { return }
        let event: DuckAISwipeNewChat.Event
        switch gesture.state {
        case .began:
            panID += 1
            event = .began(isEligible: beginIfEligible(gesture, in: hostView))
        case .changed:
            event = .moved(translation: gesture.translation(in: hostView).y)
        case .ended:
            event = .ended
        case .cancelled, .failed:
            event = .cancelled
        default:
            return
        }
        apply(pull.handle(event))
    }

    private func beginIfEligible(_ gesture: UIPanGestureRecognizer, in hostView: UIView) -> Bool {
        guard let window = hostView.window, let chrome = chromeState() else { return false }
        let homeIndicatorTop = hostView.convert(CGPoint(x: 0, y: window.bounds.maxY - window.safeAreaInsets.bottom), from: nil).y
        let eligibility = DuckAISwipeNewChat.Eligibility(isFeatureEnabled: isFeatureEnabled(),
                                                         isPhone: UIDevice.current.userInterfaceIdiom == .phone,
                                                         hasChat: webView?.url?.duckAIChatID != nil,
                                                         isKeyboardVisible: chrome.isKeyboardVisible,
                                                         isGenerating: chrome.isGenerating,
                                                         panVelocity: gesture.velocity(in: hostView),
                                                         startY: gesture.location(in: hostView).y,
                                                         bottomInsetMinY: homeIndicatorTop)
        guard eligibility.isEligible else { return false }
        haptic.prepare()
        placeHint(in: hostView, above: chrome.bottomChromeMinY ?? window.bounds.maxY - window.safeAreaInsets.bottom)
        return true
    }

    private func apply(_ effects: [DuckAISwipeNewChat.Effect]) {
        for effect in effects {
            switch effect {
            case .checkAtBottom:
                checkAtBottom()
            case .showHint(let progress, let isArmed):
                hint.update(progress: progress, isArmed: isArmed)
            case .hideHint:
                hint.hide()
            case .haptic:
                haptic.impactOccurred()
            case .startNewChat:
                onStartNewChat()
            }
        }
    }

    /// The bottom chrome doesn't move during a pull, so the hint is placed once per pan.
    private func placeHint(in hostView: UIView, above chromeMinYInWindow: CGFloat) {
        if hint.superview !== hostView {
            hint.removeFromSuperview()
            hostView.addSubview(hint)
            let bottom = hint.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
            NSLayoutConstraint.activate([
                hint.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
                hint.leadingAnchor.constraint(greaterThanOrEqualTo: hostView.leadingAnchor, constant: DuckAISwipeNewChat.Constants.hintSpacing),
                bottom
            ])
            hintBottomConstraint = bottom
        }
        hostView.bringSubviewToFront(hint)
        let chromeTop = min(hostView.convert(CGPoint(x: 0, y: chromeMinYInWindow), from: nil).y, hostView.bounds.maxY)
        hintBottomConstraint?.constant = chromeTop - hostView.bounds.maxY - DuckAISwipeNewChat.Constants.hintSpacing
    }

    private func checkAtBottom() {
        guard let webView, !isCheckInFlight else { return }
        isCheckInFlight = true
        let checkedPanID = panID
        let point = pan.location(in: webView)
        webView.evaluateJavaScript(Self.atBottomScript(at: point)) { [weak self] result, _ in
            guard let self else { return }
            self.isCheckInFlight = false
            guard checkedPanID == self.panID, result as? Bool == true, let hostView = self.hostView else { return }
            self.apply(self.pull.handle(.reachedBottom(translation: self.pan.translation(in: hostView).y)))
        }
    }

    /// Whether the nearest vertical scroller under `point` is at its bottom. When nothing overflows, the
    /// whole chat fits on screen and so is already at its bottom.
    private static func atBottomScript(at point: CGPoint) -> String {
        """
        (function(x, y) {
          let el = document.elementFromPoint(x, y);
          while (el && el !== document.documentElement) {
            const style = getComputedStyle(el);
            if (/(auto|scroll)/.test(style.overflowY) && el.scrollHeight > el.clientHeight + 1) {
              return el.scrollTop + el.clientHeight >= el.scrollHeight - 4;
            }
            el = el.parentElement;
          }
          const root = document.scrollingElement;
          return !root || root.scrollTop + innerHeight >= root.scrollHeight - 4;
        })(\(point.x), \(point.y))
        """
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Reuses the Duck.ai header's floating glass pill, which already sits over chat content.
private final class DuckAISwipeNewChatHintView: UIView {

    private enum Metrics {
        static let height: CGFloat = 44
        static let horizontalPadding: CGFloat = 16
        static let iconSpacing: CGFloat = 6
    }

    private let pill = AIChatHeaderGlassPill(cornerRadius: Metrics.height / 2)
    private let arrow = UIImageView(image: DesignSystemImages.Glyphs.Size16.arrowUp)
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        alpha = 0

        arrow.tintColor = UIColor(designSystemColor: .icons)
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        label.font = .daxSubheadSemibold()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.text = UserText.aiChatSwipeNewChatPullHint

        let stack = UIStackView(arrangedSubviews: [arrow, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Metrics.iconSpacing

        addSubview(pill)
        pill.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: topAnchor),
            pill.leadingAnchor.constraint(equalTo: leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor),
            pill.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.height),
            stack.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: Metrics.horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -Metrics.horizontalPadding),
            stack.centerYAnchor.constraint(equalTo: pill.contentView.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: pill.contentView.topAnchor, constant: Metrics.iconSpacing),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            pill.refreshGlassForCurrentTraits()
        }
    }

    func update(progress: CGFloat, isArmed: Bool) {
        layer.removeAllAnimations()
        label.text = isArmed ? UserText.aiChatSwipeNewChatReleaseHint : UserText.aiChatSwipeNewChatPullHint
        arrow.isHidden = isArmed
        alpha = progress
        transform = UIAccessibility.isReduceMotionEnabled
            ? .identity
            : CGAffineTransform(translationX: 0, y: (1 - progress) * DuckAISwipeNewChat.Constants.hintSlideDistance)
    }

    func hide() {
        UIView.animate(withDuration: DuckAISwipeNewChat.Constants.hintHideDuration) {
            self.alpha = 0
            self.transform = .identity
        }
    }
}
