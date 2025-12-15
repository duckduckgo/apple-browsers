//
//  NavigationBarBadgeAnimationView.swift
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

protocol NotificationBarViewAnimated: NSView {
    func startAnimation(_ completion: @escaping () -> Void)
    func cancelAnimation()
}

final class NavigationBarBadgeAnimationView: NSView {
    var animatedView: NotificationBarViewAnimated?

    enum AnimationType {
        case cookiePopupManaged
        case cookiePopupHidden
        case trackersBlocked(count: Int)
    }

    func prepareAnimation(_ type: AnimationType) {
        removeAnimation()
        let viewToAnimate: NotificationBarViewAnimated
        switch type {
        case .cookiePopupHidden:
            viewToAnimate = BadgeNotificationContainerView(isCosmetic: true)
        case .cookiePopupManaged:
            viewToAnimate = BadgeNotificationContainerView(isCosmetic: false)
        case .trackersBlocked(let count):
            // Create text generator for proper localization during counting animation
            let textGenerator: (Int) -> String = { currentCount in
                UserText.omnibarNotificationTrackersBlocked(currentCount)
            }
            // Use initial text for fallback (same as iOS)
            let text = UserText.omnibarNotificationTrackersBlocked(count)
            viewToAnimate = BadgeNotificationContainerView(
                customText: text,
                useShieldIcon: true,
                trackerCount: count,
                textGenerator: textGenerator
            )
        }

        addSubview(viewToAnimate)
        animatedView = viewToAnimate
        setupConstraints()
    }

    func startAnimation(completion: @escaping () -> Void) {
         self.animatedView?.startAnimation(completion)
    }

    func removeAnimation() {
        animatedView?.cancelAnimation()
        animatedView?.removeFromSuperview()
        animatedView = nil
    }

    private func setupConstraints() {
        guard let animatedView = animatedView else {
            return
        }

        animatedView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            animatedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            animatedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            animatedView.bottomAnchor.constraint(equalTo: bottomAnchor),
            animatedView.topAnchor.constraint(equalTo: topAnchor)
        ])
    }
}
