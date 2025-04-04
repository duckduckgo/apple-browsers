//
//  PullToRefreshViewAdapter.swift
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

/**
 *
 * A custom implementation of pull-to-refresh functionality that works with any UIView.
 * This class creates a transparent background UIScrollView to display the native
 * UIRefreshControl while transforming a target view in response to pull gestures.
 *
 * ## How it works:
 * 1. A transparent "fake" scroll view is placed behind the target view to host the
 *    standard UIRefreshControl
 * 2. A pan gesture recognizer tracks vertical pulls on the content
 * 3. When pulled down, the target view moves with the gesture while the refresh
 *    control appears in the background
 * 4. When pulled past the threshold, a refresh is triggered
 *
 * This approach allows for pull-to-refresh functionality in contexts where a standard
 * UIScrollView implementation isn't possible or desirable, such as with WKWebViews.
 *
 */
final class PullToRefreshViewAdapter: NSObject {

    private enum Constant {

        // Base values for portrait orientation on standard devices
        static let pullLimitRatio: CGFloat = 0.25 // 25% of container height
        static let refreshTriggerRatio: CGFloat = 0.2 // 20% of container height

        // Minimum values to ensure usability on very small screens
        static let minimumPullLimit: CGFloat = 120
        static let minimumTriggerThreshold: CGFloat = 80

        // Maximum values to prevent excessive pulling on large screens
        static let maximumPullLimit: CGFloat = 250
        static let maximumTriggerThreshold: CGFloat = 200

    }

    private var pullLimit: CGFloat {
        let containerHeight = pullableView?.bounds.height ?? UIScreen.main.bounds.height
        let calculatedLimit = containerHeight * Constant.pullLimitRatio
        return min(max(calculatedLimit, Constant.minimumPullLimit), Constant.maximumPullLimit)
    }

    private var refreshTriggerThreshold: CGFloat {
        let containerHeight = pullableView?.bounds.height ?? UIScreen.main.bounds.height
        let calculatedThreshold = containerHeight * Constant.refreshTriggerRatio
        return min(max(calculatedThreshold, Constant.minimumTriggerThreshold), Constant.maximumTriggerThreshold)
    }

    private var fakeScrollView: UIScrollView!
    private let refreshControl = UIRefreshControl()
    private var panGestureRecognizer: UIPanGestureRecognizer?

    private var isPulling = false
    private var didTriggerRefresh = false
    private var didEndRefreshing = false
    private var initialTranslationY: CGFloat = 0

    private weak var scrollView: UIScrollView?
    private weak var pullableView: UIView?
    private let onRefresh: () -> Void

    var backgroundColor: UIColor? {
        didSet {
            fakeScrollView.backgroundColor = backgroundColor ?? UIColor(designSystemColor: .background)
            // Set refresh control tint color based on background brightness
            refreshControl.tintColor = determineRefreshControlTintColor(for: backgroundColor)
        }
    }

    private func determineRefreshControlTintColor(for backgroundColor: UIColor?) -> UIColor {
        guard let backgroundColor = backgroundColor else {
            return UIColor(designSystemColor: .iconsSecondary)
        }

        let userInterfaceStyle: UIUserInterfaceStyle = backgroundColor.brightnessPercentage < 50 ? .dark : .light
        return UIColor(designSystemColor: .iconsSecondary).resolvedColor(with: .init(userInterfaceStyle: userInterfaceStyle))
    }

    /**
     * Initializes the pull-to-refresh logic with the necessary components.
     *
     * @param scrollView The scroll view that will be monitored for scroll position.
     *                   This is typically the main content scroll view (e.g., a WKWebView's scrollView)
     *                   that will determine when pulling should begin.
     *
     * @param pullableView The view that will be transformed/moved during the pull gesture.
     *                     This is the main content container that visually responds to the pull.
     *
     * @param onRefresh A closure that will be called when a refresh is triggered.
     *                  Implement your data reloading logic in this closure.
     */
    init(with scrollView: UIScrollView,
         pullableView: UIView,
         onRefresh: @escaping () -> Void) {
        self.scrollView = scrollView
        self.pullableView = pullableView
        self.onRefresh = onRefresh

        super.init()
        setupBackgroundScrollView(basedOn: pullableView)
        fakeScrollView.refreshControl = refreshControl
        setupPanGestureRecognizer()
        refreshControl.tintColor = UIColor(designSystemColor: .iconsSecondary)
    }

    private func setupBackgroundScrollView(basedOn view: UIView) {
        // Create the background scroll view that will be visible when pulling down
        fakeScrollView = UIScrollView()
        fakeScrollView.translatesAutoresizingMaskIntoConstraints = false
        fakeScrollView.isScrollEnabled = true // Enable scrolling for refresh control

        view.superview?.addSubview(fakeScrollView)
        view.superview?.sendSubviewToBack(fakeScrollView)

        NSLayoutConstraint.activate([
            fakeScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            fakeScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fakeScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fakeScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        let fakeContentView = UIView()
        fakeContentView.translatesAutoresizingMaskIntoConstraints = false
        fakeScrollView.addSubview(fakeContentView)

        // Make the content view much taller than the scroll view to allow scrolling
        NSLayoutConstraint.activate([
            fakeContentView.topAnchor.constraint(equalTo: fakeScrollView.topAnchor),
            fakeContentView.leadingAnchor.constraint(equalTo: fakeScrollView.leadingAnchor),
            fakeContentView.trailingAnchor.constraint(equalTo: fakeScrollView.trailingAnchor),
            fakeContentView.widthAnchor.constraint(equalTo: fakeScrollView.widthAnchor),
            fakeContentView.bottomAnchor.constraint(equalTo: fakeScrollView.bottomAnchor),
            fakeContentView.heightAnchor.constraint(equalToConstant: 1500) // Tall enough to scroll
        ])
    }

    private func setupPanGestureRecognizer() {
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.delegate = self
        self.panGestureRecognizer = panGestureRecognizer
        scrollView?.addGestureRecognizer(panGestureRecognizer)
    }

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            initialTranslationY = 0
        case .changed:
            let translation = gesture.translation(in: pullableView)
            handleVerticalChange(translationY: translation.y)
        case .ended, .cancelled:
            resetPullState()
            animatePullableViewToOriginalPosition()
        default:
            break
        }
    }

    private func handleVerticalChange(translationY: CGFloat) {
        guard let scrollView else { return }

        let wasNotPulling = !isPulling
        startPullingIfAtTop(of: scrollView)
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
            scrollView.bounces = false
            isPulling = true
        }
    }

    private func calculatePullDistance(translationY: CGFloat) -> CGFloat {
        let adjustedTranslation = max(0, translationY - initialTranslationY)
        // Allow full movement up to the refresh trigger threshold
        if adjustedTranslation <= refreshTriggerThreshold {
            return adjustedTranslation
        } else {
            // Apply gradually increasing resistance beyond the refresh trigger threshold
            let extraPull = adjustedTranslation - refreshTriggerThreshold

            // Quadratic resistance curve - starts gentle but increases rapidly
            let resistanceFactor = 0.4 / (1 + 0.3 * pow(extraPull / refreshTriggerThreshold, 2))
            let resistedExtraPull = extraPull * resistanceFactor

            return refreshTriggerThreshold + resistedExtraPull
        }
    }

    private func handlePullEffect(pullDistance: CGFloat) {
        // Move the pullable view down based on pull distance
        pullableView?.transform = CGAffineTransform(translationX: pullableView?.frame.origin.x ?? 0,
                                                    y: pullDistance)

        // Update the background scroll view's content offset to match the pull
        // We only adjust the content offset if not refreshing to avoid hiding the refresh spinner
        if !refreshControl.isRefreshing {
            fakeScrollView.contentOffset.y = -pullDistance
        }
    }

    private func triggerRefreshIfNeeded(pullDistance: CGFloat) {
        // Trigger refresh if pulled past threshold and not already triggered
        if pullDistance > refreshTriggerThreshold, !didTriggerRefresh {
            beginRefreshing()
        }
    }

    private func resetPullState() {
        isPulling = false
        scrollView?.bounces = true
        didTriggerRefresh = false
        if didEndRefreshing {
            refreshControl.endRefreshing()
            didEndRefreshing = false
        }
    }

    private func animatePullableViewToOriginalPosition() {
        UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveEaseInOut) {
            self.pullableView?.transform = .identity
            if !self.refreshControl.isRefreshing {
                self.fakeScrollView.contentOffset.y = 0
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

    /**
     * Ends the refreshing state and resets the UI.
     * Call this method when your data reload operation completes.
     */
    func endRefreshing() {
        didEndRefreshing = true
        if !isPulling {
            refreshControl.endRefreshing()
            animatePullableViewToOriginalPosition()
        }
    }

    /**
     * Enables or disables the refresh control.
     * Use this to temporarily disable pull-to-refresh functionality.
     *
     * @param isEnabled Whether the refresh control should be enabled.
     */
    func setRefreshControlEnabled(_ isEnabled: Bool) {
        if !isPulling {
            fakeScrollView.refreshControl = isEnabled ? refreshControl : nil
        }
    }

}

extension PullToRefreshViewAdapter: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

}
