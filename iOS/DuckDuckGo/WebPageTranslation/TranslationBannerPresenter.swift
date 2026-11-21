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

import os.log
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

    var isPresented: Bool {
        hostingController != nil
    }

    /// - Parameter addressBar: the bar the banner sits under (bar at the top) or above (bar at the bottom).
    func present(_ offer: TranslationOffer, in host: UIViewController, nextTo addressBar: UIView) {
        dismiss(animated: false)

        let banner = SwipeableTranslationBanner(offer: offer,
                                                onTranslate: { [weak self] in
                                                    // TODO: - Implement translation
                                                    Logger.webPageTranslation.info("Translation banner: Translate tapped")
                                                    self?.dismiss(animated: true)
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
        let edgeConstraint = appSettings.currentAddressBarPosition == .bottom
            ? controller.view.bottomAnchor.constraint(equalTo: addressBar.topAnchor, constant: -Constants.verticalMargin)
            : controller.view.topAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: Constants.verticalMargin)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.leadingAnchor,
                                                     constant: Constants.horizontalMargin),
            controller.view.trailingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.trailingAnchor,
                                                      constant: -Constants.horizontalMargin),
            edgeConstraint
        ])
        controller.didMove(toParent: host)
        hostingController = controller

        controller.view.alpha = 0
        UIView.animate(withDuration: 0.3) { controller.view.alpha = 1 }
        scheduleAutoDismiss()
    }

    func dismiss(animated: Bool) {
        autoDismissTask?.cancel()
        guard let controller = hostingController else { return }
        hostingController = nil

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

    /// A VoiceOver user may still be on their way to the button, so the banner stays for them.
    private func scheduleAutoDismiss() {
        let delay = autoDismissDelay
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
