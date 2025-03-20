//
//  PullToRefreshLogic.swift
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
import WebKit

final class PullToRefreshLogic: NSObject {

    private enum Constant {

        static let pullLimit: CGFloat = 200
        static let refreshTriggerThreshold: CGFloat = 160

    }

    private let refreshControl = UIRefreshControl()
    private var panGestureRecognizer: UIPanGestureRecognizer?

    private var isPulling = false
    private var didTriggerRefresh = false
    private var didEndRefreshing = false

    private weak var webView: WKWebView?
    private weak var webViewContainer: UIView?
    private let scrollView: UIScrollView
    private let onRefresh: () -> Void

    init(with webView: WKWebView,
         webViewContainer: UIView,
         scrollView: UIScrollView,
         onRefresh: @escaping () -> Void) {
        self.webView = webView
        self.webViewContainer = webViewContainer
        self.scrollView = scrollView
        self.onRefresh = onRefresh

        super.init()
        scrollView.refreshControl = refreshControl
        setupPanGestureRecognizer()
        refreshControl.tintColor = .label
    }

    private func setupPanGestureRecognizer() {
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.delegate = self
        self.panGestureRecognizer = panGestureRecognizer
        webView?.addGestureRecognizer(panGestureRecognizer)
    }

    private var initialTranslationY: CGFloat = 0
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let webView else { return }
        switch gesture.state {
        case .began:
            initialTranslationY = 0
        case .changed:
            let translation = gesture.translation(in: webView.superview)
            handleVerticalChange(translationY: translation.y)
        case .ended, .cancelled:
            resetPullState()
            animateCardToOriginalPosition()
        default:
            break
        }
    }

    private func handleVerticalChange(translationY: CGFloat) {
        guard let webView else { return }

        let wasNotPulling = !isPulling
        startPullingIfAtTop(of: webView.scrollView)
        if isPulling {
            if wasNotPulling {
                initialTranslationY = translationY
            }
            let pullDistance = calculatePullDistance(translationY: translationY)
            handlePullEffect(pullDistance: pullDistance)
            triggerRefreshIfNeeded(pullDistance: pullDistance)
        }
    }

    private func startPullingIfAtTop(of scrollView: UIScrollView) {
        if scrollView.contentOffset.y < 0 {
            webView?.scrollView.bounces = false
            isPulling = true
        }
    }

    private func calculatePullDistance(translationY: CGFloat) -> CGFloat {
        let adjustedTranslation = max(0, translationY - initialTranslationY)
        return min(adjustedTranslation, Constant.pullLimit)
    }

    private func handlePullEffect(pullDistance: CGFloat) {
        // Move the webView container down based on pull distance
        webViewContainer?.transform = CGAffineTransform(translationX: webView?.frame.origin.x ?? 0, y: pullDistance)

        // Update the background scroll view's content offset to match the pull
        // We only adjust the content offset if not refreshing to avoid hiding the refresh spinner
        if !refreshControl.isRefreshing {
            scrollView.contentOffset.y = -pullDistance
        }
    }

    private func triggerRefreshIfNeeded(pullDistance: CGFloat) {
        // Trigger refresh if pulled past threshold and not already triggered
        if pullDistance > Constant.refreshTriggerThreshold, !didTriggerRefresh {
            beginRefreshing()
        }
    }

    private func resetPullState() {
        isPulling = false
        webView?.scrollView.bounces = true
        didTriggerRefresh = false
        if didEndRefreshing {
            refreshControl.endRefreshing()
            didEndRefreshing = false
        }
    }

    private func animateCardToOriginalPosition() {
        UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveEaseInOut) {
            self.webViewContainer?.transform = .identity
            if !self.refreshControl.isRefreshing {
                self.scrollView.contentOffset.y = 0
            }
        }
    }

    private func beginRefreshing() {
        didEndRefreshing = false
        refreshControl.beginRefreshing()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        didTriggerRefresh = true
        onRefresh()
    }

    func endRefreshing() {
        didEndRefreshing = true
        if !isPulling {
            refreshControl.endRefreshing()
            animateCardToOriginalPosition()
        }
    }

    func setRefreshControlEnabled(_ isEnabled: Bool) {
        if !isPulling {
            scrollView.refreshControl = isEnabled ? refreshControl : nil
        }
    }

}

extension PullToRefreshLogic: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

}
