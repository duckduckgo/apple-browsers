//
//  OmniBarNotificationAnimator.swift
//  DuckDuckGo
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

import UIKit

enum OmniBarNotificationType {
    case cookiePopupManaged
    case cookiePopupHidden
    case trackersBlocked(count: Int)
}

final class OmniBarNotificationAnimator: NSObject {

    // Work item for cancellable delayed animation start
    private var animationStartWorkItem: DispatchWorkItem?

    // Work item for cancellable delayed completion
    private var completionWorkItem: DispatchWorkItem?

    func showNotification(_ type: OmniBarNotificationType, in omniBar: any OmniBarView, viewController: UIViewController, completion: (() -> Void)? = nil) {

        omniBar.notificationContainer.alpha = 0
        omniBar.notificationContainer.prepareAnimation(type, in: viewController)
        omniBar.textField.alpha = 0

        let fadeDuration = Constants.Duration.fade
        let animationStartOffset = fadeDuration

        // Fade in the notification container
        UIView.animate(withDuration: fadeDuration) {
            omniBar.notificationContainer.alpha = 1
        }

        // Create cancellable work item for animation start
        let startWorkItem = DispatchWorkItem { [weak self, weak omniBar] in
            guard let omniBar = omniBar else { return }

            omniBar.notificationContainer.startAnimation {

                UIView.animate(withDuration: fadeDuration) {
                    omniBar.textField.alpha = 1
                    omniBar.privacyInfoContainer.alpha = 1
                }

                UIView.animate(withDuration: fadeDuration, delay: fadeDuration) {
                    omniBar.notificationContainer.alpha = 0
                }

                // Create cancellable work item for completion
                let completionWorkItem = DispatchWorkItem {
                    omniBar.notificationContainer.removePreviousNotification()
                    completion?()
                }

                self?.completionWorkItem = completionWorkItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 2 * fadeDuration, execute: completionWorkItem)
            }
        }

        animationStartWorkItem = startWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + animationStartOffset, execute: startWorkItem)
    }

    func cancelAnimations(in omniBar: any OmniBarView) {
        // Cancel any pending work items to prevent delayed execution
        animationStartWorkItem?.cancel()
        animationStartWorkItem = nil

        completionWorkItem?.cancel()
        completionWorkItem = nil

        // Remove all running layer animations
        omniBar.notificationContainer.layer.removeAllAnimations()
        omniBar.textField.layer.removeAllAnimations()
        omniBar.privacyInfoContainer.layer.removeAllAnimations()

        // Reset visual state
        omniBar.notificationContainer.removePreviousNotification()
        omniBar.notificationContainer.alpha = 0
        omniBar.textField.alpha = 1
        omniBar.privacyInfoContainer.alpha = 1
    }
}

private enum Constants {
    enum Duration {
        static let fade: TimeInterval = 0.25
    }
}
