//
//  TranslationBannerPresenter.swift
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

import ConcurrencyExtensions
import SwiftUI
import UIKit
import WebPageTranslation

/// Shows the translation banner over a tab, next to the address bar, until it times out, is swiped
/// away, or the tab dismisses it.
@MainActor
final class TranslationBannerPresenter {

    private enum Constants {
        static let horizontalMargin: CGFloat = 24
        static let verticalMargin: CGFloat = 8
    }

    private let appSettings: AppSettings
    private let autoDismissDelay: TimeInterval
    private let isVoiceOverRunning: @MainActor () -> Bool

    private var hostingController: UIViewController?
    private var autoDismissTask: Task<Void, Never>?

    init(appSettings: AppSettings,
         autoDismissDelay: TimeInterval = 5,
         isVoiceOverRunning: @escaping @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning }) {
        self.appSettings = appSettings
        self.autoDismissDelay = autoDismissDelay
        self.isVoiceOverRunning = isVoiceOverRunning
    }

    private weak var addressBar: UIView?
    private var nextToBarConstraint: NSLayoutConstraint?
    private var clearOfChromeConstraint: NSLayoutConstraint?

    /// How far the chrome reaches in from the host's edges once the address bar has scrolled away (the
    /// collapsed pill included). The banner never goes past it, so it stays on screen while the bar is gone.
    var chromeInsets: UIEdgeInsets = .zero {
        didSet { updateClearOfChromeConstraint() }
    }
    
    private var isBarAtBottom: Bool {
        appSettings.currentAddressBarPosition == .bottom
    }

    var isPresented: Bool {
        hostingController != nil
    }

    /// - Parameters:
    ///   - addressBar: the bar the banner sits under (bar at the top) or above (bar at the bottom).
    ///   - onTranslate: called when the user taps Translate; the banner then goes away.
    func present(_ offer: TranslationOffer,
                 in host: UIViewController,
                 nextTo addressBar: UIView,
                 onTranslate: @escaping () -> Void = {}) {
        dismiss(animated: false)

        let banner = SwipeableTranslationBanner(offer: offer,
                                                onTranslate: { [weak self] in
                                                    self?.dismiss(animated: true)
                                                    onTranslate()
                                                },
                                                onDismiss: { [weak self] animated in
                                                    self?.dismiss(animated: animated)
                                                },
                                                onDraggingChanged: { [weak self] isDragging in
                                                    // Never time out under the user's finger.
                                                    if isDragging {
                                                        self?.autoDismissTask?.cancel()
                                                    } else {
                                                        self?.scheduleAutoDismiss()
                                                    }
                                                })
        let controller = UIHostingController(rootView: banner)
        controller.view.backgroundColor = .clear
        controller.view.translatesAutoresizingMaskIntoConstraints = false

        host.addChild(controller)
        host.view.addSubview(controller.view)
        let bannerView: UIView = controller.view
        let safeArea = host.view.safeAreaLayoutGuide
        // Next to the bar while it's on screen; once it scrolls away, held clear of the safe area and the chrome.
        // Pinned to where the bar is drawn, not to the bar: the chrome hides and shrinks it with transforms, which
        // Auto Layout doesn't see. followAddressBar() keeps the two in step.
        let nextToBar = isBarAtBottom
            ? bannerView.bottomAnchor.constraint(equalTo: host.view.topAnchor)
            : bannerView.topAnchor.constraint(equalTo: host.view.topAnchor)
        nextToBar.priority = .defaultHigh
        // The window's, not the tab's: the tab's safe area covers the chrome, so it would hold the banner where the bar was.
        let screenSafeArea = (host.view.window ?? host.view).safeAreaLayoutGuide
        let inSafeArea = isBarAtBottom
            ? bannerView.bottomAnchor.constraint(lessThanOrEqualTo: screenSafeArea.bottomAnchor, constant: -Constants.verticalMargin)
            : bannerView.topAnchor.constraint(greaterThanOrEqualTo: screenSafeArea.topAnchor, constant: Constants.verticalMargin)
        let clearOfChrome = isBarAtBottom
            ? bannerView.bottomAnchor.constraint(lessThanOrEqualTo: host.view.bottomAnchor)
            : bannerView.topAnchor.constraint(greaterThanOrEqualTo: host.view.topAnchor)
        let maximumWidth = NewTabPageView.escapeHatchMaximumWidth(horizontalSizeClass: UserInterfaceSizeClass(host.traitCollection.horizontalSizeClass))
        let fillWidth = bannerView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, constant: -2 * Constants.horizontalMargin)
        fillWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            // Spans the safe area like on a phone, but on a wide screen stops growing and stays centred.
            bannerView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            bannerView.widthAnchor.constraint(lessThanOrEqualTo: safeArea.widthAnchor, constant: -2 * Constants.horizontalMargin),
            bannerView.widthAnchor.constraint(lessThanOrEqualToConstant: maximumWidth),
            fillWidth,
            nextToBar,
            inSafeArea,
            clearOfChrome
        ])
        controller.didMove(toParent: host)
        hostingController = controller
        self.addressBar = addressBar
        nextToBarConstraint = nextToBar
        clearOfChromeConstraint = clearOfChrome
        followAddressBar()
        updateClearOfChromeConstraint()

        controller.view.alpha = 0
        UIView.animate(withDuration: 0.3) { controller.view.alpha = 1 }
        scheduleAutoDismiss()
    }

    func dismiss(animated: Bool) {
        autoDismissTask?.cancel()
        guard let controller = hostingController else { return }
        hostingController = nil
        nextToBarConstraint = nil
        clearOfChromeConstraint = nil

        let remove = {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: {
                controller.view.alpha = 0
            }, completion: { _ in
                remove()
            })
        } else {
            remove()
        }
    }

    /// Moves the banner with the address bar as the bar shows, hides or shrinks.
    func followAddressBar() {
        guard let constraint = nextToBarConstraint, let addressBar, let hostView = hostingController?.view.superview else { return }
        let barFrame = addressBar.convert(addressBar.bounds, to: hostView)
        constraint.constant = isBarAtBottom
            ? barFrame.minY - Constants.verticalMargin
            : barFrame.maxY + Constants.verticalMargin
    }

    private func updateClearOfChromeConstraint() {
        guard let constraint = clearOfChromeConstraint else { return }
        constraint.constant = isBarAtBottom
            ? -(chromeInsets.bottom + Constants.verticalMargin)
            : chromeInsets.top + Constants.verticalMargin
    }

    /// A VoiceOver user may still be on their way to the button, so the banner stays for them.
    private func scheduleAutoDismiss() {
        let delay = autoDismissDelay
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(interval: delay)
            guard let self, !Task.isCancelled, !self.isVoiceOverRunning() else { return }
            self.dismiss(animated: true)
        }
    }
}

/// The banner follows a vertical drag either way; a long or quick enough drag carries it off and dismisses it.
private struct SwipeableTranslationBanner: View {

    private enum Constants {
        static let dismissDistance: CGFloat = 40
        static let minimumExitDistance: CGFloat = 120
        static let exitDuration: TimeInterval = 0.2
    }

    let offer: TranslationOffer
    let onTranslate: () -> Void
    let onDismiss: (_ animated: Bool) -> Void
    let onDraggingChanged: (_ isDragging: Bool) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isLeaving = false

    var body: some View {
        TranslationBannerView(offer: offer, onTranslate: onTranslate)
            .offset(y: dragOffset)
            .opacity(isLeaving ? 0 : 1)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onDraggingChanged(true)
                        }
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        isDragging = false
                        let predicted = value.predictedEndTranslation.height
                        guard max(abs(dragOffset), abs(predicted)) > Constants.dismissDistance else {
                            withAnimation(.spring()) { dragOffset = 0 }
                            onDraggingChanged(false)
                            return
                        }
                        // Carry on in the flick's direction, then remove without a second fade.
                        let direction: CGFloat = predicted == 0 ? (dragOffset < 0 ? -1 : 1) : (predicted < 0 ? -1 : 1)
                        withAnimation(.easeOut(duration: Constants.exitDuration)) {
                            dragOffset = direction * max(abs(predicted), Constants.minimumExitDistance)
                            isLeaving = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.exitDuration) { onDismiss(false) }
                    }
            )
            .accessibilityAction(.escape) { onDismiss(true) }
    }
}
