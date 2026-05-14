//
//  NavigationBarBadgeAnimator.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Cocoa

protocol NavigationBarBadgeAnimatorDelegate: AnyObject {
    func didFinishAnimating(type: NavigationBarBadgeAnimationView.AnimationType)
}

final class NavigationBarBadgeAnimator: NSObject {

    // Priority queue system to manage the animations
    enum AnimationPriority: Comparable {
        case high  // Tracker notifications (shown first)
        case low   // Cookie notifications (shown after trackers)

        static func < (lhs: AnimationPriority, rhs: AnimationPriority) -> Bool {
            switch (lhs, rhs) {
            case (.low, .high): return true
            default: return false
            }
        }
    }

    struct QueuedAnimation {
        let type: NavigationBarBadgeAnimationView.AnimationType
        let priority: AnimationPriority
        var selectedTab: Tab?
        let buttonsContainer: NSView
        let notificationBadgeContainer: NavigationBarBadgeAnimationView
    }

    private var animationID: UUID?
    private(set) var isAnimating = false
    /// Tracks whether the shield animation is playing (managed externally by AddressBarButtonsViewController)
    /// Used to prevent new badge animations from starting while shield animation is in progress
    var isShieldAnimationInProgress = false
    private(set) var animationQueue: [QueuedAnimation] = []
    private(set) var currentAnimationPriority: AnimationPriority?
    private(set) var currentAnimationType: NavigationBarBadgeAnimationView.AnimationType?
    private weak var currentTab: Tab?
    private var shouldAutoProcessNextAnimation = true
    private weak var currentButtonsContainer: NSView?
    private weak var currentNotificationContainer: NavigationBarBadgeAnimationView?

    weak var delegate: NavigationBarBadgeAnimatorDelegate?

    private enum ButtonsFade {
        case start
        case end
    }

    func showNotification(withType type: NavigationBarBadgeAnimationView.AnimationType,
                          buttonsContainer: NSView,
                          notificationBadgeContainer: NavigationBarBadgeAnimationView) {
        isAnimating = true

        let newAnimationID = UUID()
        self.animationID = newAnimationID
        self.currentButtonsContainer = buttonsContainer
        self.currentNotificationContainer = notificationBadgeContainer

        notificationBadgeContainer.prepareAnimation(type)

        animateButtonsFade(.start,
                           buttonsContainer: buttonsContainer,
                           notificationBadgeContainer: notificationBadgeContainer) {

            notificationBadgeContainer.startAnimation { [weak self] in
                if self?.animationID == newAnimationID {
                    self?.animateButtonsFade(.end,
                                       buttonsContainer: buttonsContainer,
                                       notificationBadgeContainer: notificationBadgeContainer) {
                        // Capture the type before clearing state
                        let finishedType = self?.currentAnimationType
                        self?.isAnimating = false
                        self?.currentAnimationPriority = nil
                        self?.currentAnimationType = nil
                        self?.currentButtonsContainer = nil
                        self?.currentNotificationContainer = nil
                        if let finishedType = finishedType {
                            self?.delegate?.didFinishAnimating(type: finishedType)
                        }

                        // Only auto-process next animation if flag is set
                        // (tracker notifications will manually process after shield animation)
                        if self?.shouldAutoProcessNextAnimation == true {
                            self?.processNextAnimation()
                        }
                        self?.shouldAutoProcessNextAnimation = true  // Reset for next animation
                    }
                }
            }
        }
    }

    private func animateButtonsFade(_ fadeType: ButtonsFade,
                                    buttonsContainer: NSView,
                                    notificationBadgeContainer: NavigationBarBadgeAnimationView,
                                    completionHandler: @escaping (() -> Void)) {

        let animationDuration: CGFloat = 0.25

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            if fadeType == .start {
                buttonsContainer.animator().alphaValue = 0
            } else if fadeType == .end {
                notificationBadgeContainer.animator().alphaValue = 0
            }
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                if fadeType == .start {
                    notificationBadgeContainer.animator().alphaValue = 1
                } else if fadeType == .end {
                    buttonsContainer.animator().alphaValue = 1
                }
            } completionHandler: {
                completionHandler()
            }
        }
    }

    // MARK: - Priority Queue Management

    func enqueueAnimation(_ type: NavigationBarBadgeAnimationView.AnimationType,
                          priority: AnimationPriority,
                          tab: Tab? = nil,
                          buttonsContainer: NSView,
                          notificationBadgeContainer: NavigationBarBadgeAnimationView) {
        let queuedAnimation = QueuedAnimation(
            type: type,
            priority: priority,
            selectedTab: tab,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )

        // Add to queue
        animationQueue.append(queuedAnimation)

        // Sort by priority (high priority first) - matches iOS behavior
        animationQueue.sort { $0.priority > $1.priority }

        // Start processing if not already animating and shield animation is not in progress
        if !isAnimating && !isShieldAnimationInProgress {
            processNextAnimation()
        }
    }

    func processNextAnimation() {
        guard !isAnimating, !isShieldAnimationInProgress, !animationQueue.isEmpty else { return }

        let nextAnimation = animationQueue.removeFirst()
        currentAnimationPriority = nextAnimation.priority
        currentAnimationType = nextAnimation.type
        currentTab = nextAnimation.selectedTab

        // For tracker notifications, disable auto-processing so shield animation can play first
        // This must be set when the animation STARTS, not when it's queued
        if case .trackersBlocked = nextAnimation.type {
            shouldAutoProcessNextAnimation = false
        }

        showNotification(
            withType: nextAnimation.type,
            buttonsContainer: nextAnimation.buttonsContainer,
            notificationBadgeContainer: nextAnimation.notificationBadgeContainer
        )
    }

    func cancelPendingAnimations() {
        // Clear the queue
        animationQueue.removeAll()

        // Reset flags to default state
        shouldAutoProcessNextAnimation = true
        isShieldAnimationInProgress = false

        // Stop current animation and restore UI state
        if isAnimating {
            // Restore buttons container visibility
            currentButtonsContainer?.alphaValue = 1
            // Hide notification container
            currentNotificationContainer?.alphaValue = 0
            currentNotificationContainer?.removeAnimation()

            isAnimating = false
            animationID = nil
            currentAnimationPriority = nil
            currentAnimationType = nil
            currentTab = nil
            currentButtonsContainer = nil
            currentNotificationContainer = nil
        }
    }

    func handleTabSwitch(to tab: Tab) {
        // If current animation is for a different tab, cancel it
        if let currentTab = currentTab, currentTab !== tab {
            cancelPendingAnimations()
        }

        // Remove queued animations for different tabs
        animationQueue.removeAll { queuedAnimation in
            guard let queuedTab = queuedAnimation.selectedTab else { return false }
            return queuedTab !== tab
        }
    }

    /// Sets whether to automatically process the next animation after the current one completes
    /// Used for tracker notifications that need to play shield animation before processing next in queue
    func setAutoProcessNextAnimation(_ enabled: Bool) {
        shouldAutoProcessNextAnimation = enabled
    }
}
