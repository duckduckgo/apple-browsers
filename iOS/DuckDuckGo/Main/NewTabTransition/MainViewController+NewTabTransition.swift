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

import UIKit
import os

/// The browser opens its new tabs through `newTabTransitions`; see `NewTabTransitionCoordinator`.
extension MainViewController: NewTabTransitionHost {

    /// Off in UI tests, which expect each screen to settle at once.
    var isNewTabTransitionEnabled: Bool {
        featureFlagger.isFeatureOn(.newTabTransition)
            && NewTabTransitionConfigurationStore.shared.configuration.isEnabled
            && !ProcessInfo.isRunningUITests
    }

    var newPageView: UIView { view }

    func makeNewTabTransition(from start: NewTabTransitionCoordinator.Start) -> NewTabTransitioning? {
        guard isNewTabTransitionEnabled, let oldScreen = oldScreen(for: start) else { return nil }
        logMenuViews(around: oldScreen)
        return NewTabTransition.begin(over: oldScreen,
                                      dimmedBy: dimmingOverOldScreen(for: start),
                                      from: start == .tabManager ? .tabManager : .inTab,
                                      tapLocation: newTabTouchLocationRecorder.lastTouchLocation,
                                      configuration: NewTabTransitionConfigurationStore.shared.configuration)
    }

    /// Even unanimated, dismissal removes the screen a moment later, so it stays hidden until then.
    func closePresentedScreenUnseen(then completion: @escaping () -> Void) {
        presentedViewController?.presentationController?.containerView?.isHidden = true
        let startedAt = CACurrentMediaTime()
        dismiss(animated: false) {
            Self.transitionLogger.debug("Presented screen closed after \(Int((CACurrentMediaTime() - startedAt) * 1000), privacy: .public) ms")
            completion()
        }
    }

    func dismissPresentedScreen(then completion: @escaping () -> Void) {
        dismiss(animated: true, completion: completion)
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

    private static let transitionLogger = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "NewTabTransition")

    private func logMenuViews(around oldScreen: UIView) {
        func menus(in root: UIView, path: String) -> [String] {
            let name = String(describing: type(of: root))
            let here = name.contains("Menu") || name.contains("Platter") ? ["\(path)/\(name) a=\(root.alpha) hidden=\(root.isHidden)"] : []
            return here + root.subviews.flatMap { menus(in: $0, path: path + "/" + name) }
        }
        let windowLevel = (oldScreen.window?.subviews ?? []).map { "\(type(of: $0)) underOld=\($0.isDescendant(of: oldScreen))" }
        Self.transitionLogger.debug("Window subviews: \(windowLevel, privacy: .public)")
        Self.transitionLogger.debug("Menu views in window: \(oldScreen.window.map { menus(in: $0, path: "") } ?? [], privacy: .public)")
        Self.transitionLogger.debug("Menu views in old screen: \(menus(in: oldScreen, path: ""), privacy: .public)")
    }

    /// The transition hides the sheet while UIKit's non-animated dismissal finishes behind it.
    /// The new tab's keyboard waits for it, since focus asked for while a screen is still presented is refused.
    func dismissPresentedSheetInstantly() {
        let releaseKeyboard = newTabTransitions.current?.keyboardGate.hold()
        presentedViewController?.dismiss(animated: false) { releaseKeyboard?() }
    }

    func installNewTabTouchLocationRecorderIfNeeded() {
        guard let window = view.window, newTabTouchLocationRecorder.view !== window else { return }
        newTabTouchLocationRecorder.onTouchBegan = { [weak self] in self?.newTabTransitions.finishCurrent() }
        window.addGestureRecognizer(newTabTouchLocationRecorder)
    }

    private static var keyboardFocusLogger: NSObjectProtocol?

    private static var keyboardHideLogger: NSObjectProtocol?

    func installKeyboardFocusLoggerIfNeeded() {
        guard Self.keyboardFocusLogger == nil else { return }
        Self.keyboardFocusLogger = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] note in
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? -1
            self?.logFirstResponder("Keyboard will show (duration \(duration))")
        }
        Self.keyboardHideLogger = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.logFirstResponder("Keyboard will hide")
        }
    }

    func logFirstResponder(_ moment: String) {
        func firstResponder(in root: UIView) -> UIView? {
            if root.isFirstResponder { return root }
            for sub in root.subviews { if let found = firstResponder(in: sub) { return found } }
            return nil
        }
        let responder = view.window.flatMap { firstResponder(in: $0) }
        Self.transitionLogger.debug("\(moment, privacy: .public): first responder \(String(describing: responder.map { type(of: $0) }), privacy: .public), presented \(String(describing: self.presentedViewController.map { type(of: $0) }), privacy: .public)")
    }
}
