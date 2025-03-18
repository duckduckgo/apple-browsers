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

    private var panGestureRecognizer: UIPanGestureRecognizer?
    private let refreshControl = UIRefreshControl()

    private var isPulling = false
    private var didTriggerRefresh: Bool = false
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
        setupPanGestureRecognizer()
        scrollView.refreshControl = refreshControl
        refreshControl.tintColor = .label
    }

    private func setupPanGestureRecognizer() {
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.delegate = self
        self.panGestureRecognizer = panGestureRecognizer
        webView?.addGestureRecognizer(panGestureRecognizer)
    }

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let webView, let webViewContainer else { return }
        let translation = gesture.translation(in: webView.superview)
        switch gesture.state {
        case .changed:
            startPullingIfAtTop(of: webView.scrollView)
            if isPulling {
                let pullDistance = calculatePullDistance(translation: translation)
                handlePullEffect(pullDistance: pullDistance)
                triggerRefreshIfNeeded(pullDistance: pullDistance)
            }
        case .ended, .cancelled:
            resetPullState()
            animateCardToOriginalPosition()
        default:
            break
        }
    }

    private func startPullingIfAtTop(of scrollView: UIScrollView) {
        if scrollView.contentOffset.y < 0 {
            isPulling = true
        }
    }

    private func calculatePullDistance(translation: CGPoint) -> CGFloat {
        // Limit the pull distance to the defined maximum
        return max(0, min(translation.y, Constant.pullLimit))
    }

    private func handlePullEffect(pullDistance: CGFloat) {
        if pullDistance > 0 {
            // Keep the webView at the top while pulling
            webView?.scrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        }
        // Move the webView container down based on pull distance
        webViewContainer?.transform = CGAffineTransform(translationX: webView?.frame.origin.x ?? 0, y: pullDistance)

        // Update the background scroll view's content offset to match the pull
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
        didTriggerRefresh = false
        if didEndRefreshing {
            refreshControl.endRefreshing()
            didEndRefreshing = false
        }
    }

    private func animateCardToOriginalPosition() {
        UIView.animate(withDuration: 0.5,
                       delay: 0,
                       usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0.7,
                       options: .curveEaseOut,
                       animations: {
            self.webViewContainer?.transform = .identity
            self.scrollView.contentOffset.y = 0
        }, completion: nil)
    }

    private func beginRefreshing() {
        didEndRefreshing = false
        refreshControl.beginRefreshing()
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
