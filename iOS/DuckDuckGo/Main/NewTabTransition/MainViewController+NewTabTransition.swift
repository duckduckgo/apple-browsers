//
//  MainViewController+NewTabTransition.swift
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

import Common
import UIKit

/// The browser opens its new tabs through `newTabTransitions`; see `NewTabTransitionCoordinator`.
extension MainViewController: NewTabTransitionHost {

    /// iPhone only. Off in UI tests, which expect each screen to settle at once.
    var isNewTabTransitionEnabled: Bool {
        !DevicePlatform.isIpad
            && featureFlagger.isFeatureOn(.newTabTransition)
            && NewTabTransitionConfigurationStore.shared.configuration.isEnabled
            && !ProcessInfo.isRunningUITests
    }

    var newPageView: UIView { view }

    func makeNewTabTransition(from start: NewTabTransitionCoordinator.Start, raisesKeyboard: Bool) -> NewTabTransitioning? {
        guard isNewTabTransitionEnabled, let oldScreen = oldScreen(for: start) else { return nil }
        return NewTabTransition.begin(over: oldScreen,
                                      pageContent: viewCoordinator.contentContainer,
                                      dimmedBy: dimmingOverOldScreen(for: start),
                                      newPageRaisesKeyboard: raisesKeyboard,
                                      from: start == .tabManager ? .tabManager : .inTab,
                                      tapLocation: newTabTouchLocationRecorder.lastTouchLocation,
                                      configuration: NewTabTransitionConfigurationStore.shared.configuration)
    }

    /// Even unanimated, dismissal removes the screen a moment later, so it stays hidden until then.
    func closePresentedScreenUnseen(then completion: @escaping () -> Void) {
        guard let presented = presentedViewController, !presented.isBeingDismissed else { return completion() }
        presented.presentationController?.containerView?.isHidden = true
        dismiss(animated: false) { [weak self] in
            self?.newTabPageWasUncovered()
            completion()
        }
    }

    /// The new tab page waits for nothing to cover it before it asks for its keyboard; a sheet closing tells no one else.
    private func newTabPageWasUncovered() {
        recordPendingNewTabPagePresentationIfVisible()
    }

    func dismissPresentedScreen(then completion: @escaping () -> Void) {
        dismiss(animated: true, completion: completion)
    }

    /// Without the transition there is nothing to wait for, as before.
    func afterKeyboardLeaves(_ action: @escaping () -> Void) {
        guard isNewTabTransitionEnabled, keyboardShowing, let window = view.window else { return action() }
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
            observer.map(NotificationCenter.default.removeObserver)
            action()
        }
        window.endEditing(true)
    }

    /// The screen the new tab replaces: the browser alone, the browser with what it presents, or the tab manager.
    private func oldScreen(for start: NewTabTransitionCoordinator.Start) -> UIView? {
        switch start {
        case .page: return view
        case .presentedScreen: return view.window
        case .tabManager: return presentedViewController?.view
        }
    }

    /// A dimmed sheet over the browser leaves out of the snapshot, so the old screen starts at its dim instead.
    private func dimmingOverOldScreen(for start: NewTabTransitionCoordinator.Start) -> CGFloat {
        guard start == .page,
              let sheet = presentedViewController?.presentationController as? UISheetPresentationController,
              sheet.largestUndimmedDetentIdentifier == nil else { return 0 }
        return NewTabTransitionTuning.sheetBackdropDimming
    }

    /// The transition hides the sheet while UIKit's non-animated dismissal finishes behind it.
    /// The new tab's keyboard waits for it, since focus asked for while a screen is still presented is refused.
    func dismissPresentedSheetInstantly() {
        let releaseKeyboard = newTabTransitions.current?.keyboardGate.hold()
        presentedViewController?.dismiss(animated: false) { [weak self] in
            self?.newTabPageWasUncovered()
            releaseKeyboard?()
        }
    }

    func installNewTabTouchLocationRecorderIfNeeded() {
        guard let window = view.window, newTabTouchLocationRecorder.view !== window else { return }
        window.addGestureRecognizer(newTabTouchLocationRecorder)
    }
}
