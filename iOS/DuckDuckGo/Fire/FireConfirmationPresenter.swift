//
//  FireConfirmationPresenter.swift
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

import Foundation
import UIKit
import SwiftUI
import Common
import FoundationExtensions
import Core
import MetricBuilder

struct FireConfirmationPresenter {

    @MainActor
    func presentFireConfirmation(on viewController: UIViewController,
                                 attachPopoverTo source: AnyObject,
                                 tabViewModel: TabViewModel?,
                                 pixelSource: FireRequest.Source,
                                 fireContext: ScopedFireConfirmationViewModel.FireContext,
                                 browsingMode: BrowsingMode,
                                 onConfirm: @escaping (FireRequest) -> Void,
                                 onCancel: @escaping () -> Void) {
        let sourceRect = (source as? UIView)?.bounds ?? .zero
        presentScopeConfirmationSheet(on: viewController, from: source, sourceRect: sourceRect, tabViewModel: tabViewModel, pixelSource: pixelSource, fireContext: fireContext, browsingMode: browsingMode, onConfirm: onConfirm, onCancel: onCancel)
    }

    @MainActor
    func presentFireConfirmation(on viewController: UIViewController,
                                 sourceRect: CGRect,
                                 tabViewModel: TabViewModel?,
                                 pixelSource: FireRequest.Source,
                                 fireContext: ScopedFireConfirmationViewModel.FireContext,
                                 browsingMode: BrowsingMode,
                                 onConfirm: @escaping (FireRequest) -> Void,
                                 onCancel: @escaping () -> Void) {
        guard let window = UIApplication.shared.firstKeyWindow else {
            assertionFailure("No key window available")
            return
        }
        presentScopeConfirmationSheet(on: viewController, from: window, sourceRect: sourceRect, tabViewModel: tabViewModel, pixelSource: pixelSource, fireContext: fireContext, browsingMode: browsingMode, onConfirm: onConfirm, onCancel: onCancel)
    }

    // MARK: - Scope-based Confirmation

    @MainActor
    private func presentScopeConfirmationSheet(on viewController: UIViewController,
                                               from source: AnyObject,
                                               sourceRect: CGRect,
                                               tabViewModel: TabViewModel?,
                                               pixelSource: FireRequest.Source,
                                               fireContext: ScopedFireConfirmationViewModel.FireContext,
                                               browsingMode: BrowsingMode,
                                               onConfirm: @escaping (FireRequest) -> Void,
                                               onCancel: @escaping () -> Void) {
        let viewModel = ScopedFireConfirmationViewModel(tabViewModel: tabViewModel,
                                                        source: pixelSource,
                                                        fireContext: fireContext,
                                                        browsingMode: browsingMode,
                                                        onConfirm: { [weak viewController] fireOptions in
                                                            viewController?.dismiss(animated: true) {
                                                                onConfirm(fireOptions)
                                                            }
                                                        },
                                                        onCancel: { [weak viewController] in
                                                            viewController?.dismiss(animated: true) {
                                                                onCancel()
                                                            }
                                                        })

        let confirmationView = ScopedFireConfirmationView(viewModel: viewModel)
        let hostingController = makeHostingController(with: confirmationView)
        // Prevent swipe-to-dismiss for the experiment flow: the user must make an
        // explicit choice (fire or cancel) to keep the locked-controls state consistent.
        if case .duckAIOnboarding = fireContext {
            hostingController.isModalInPresentation = true
        }
            let presentingWidth = viewController.view.frame.width
            configurePresentation(for: hostingController,
                                  source: source,
                                  sourceRect: sourceRect,
                                  presentingWidth: presentingWidth)
            viewController.present(hostingController, animated: true)
        }
    
    // MARK: - Shared Presentation Helpers
        
    private func makeHostingController<Content: View>(with view: Content) -> UIHostingController<Content> {
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.backgroundColor = UIColor(designSystemColor: .backgroundTertiary)
        hostingController.modalTransitionStyle = .coverVertical
        hostingController.modalPresentationStyle = DevicePlatform.isIpad ? .popover : .pageSheet
        return hostingController
    }
    
    private func configurePresentation<Content: View>(for hostingController: UIHostingController<Content>,
                                                      source: AnyObject,
                                                      sourceRect: CGRect,
                                                      presentingWidth: CGFloat) {
        if let popoverController = hostingController.popoverPresentationController {
            configurePopoverSource(popoverController, source: source, sourceRect: sourceRect)
            
            let sheetHeight = calculateSheetHeight(for: hostingController, width: Constants.iPadSheetWidth)
            hostingController.preferredContentSize = CGSize(width: Constants.iPadSheetWidth, height: sheetHeight)
            
            configureSheetDetents(popoverController.adaptiveSheetPresentationController,
                                 hostingController: hostingController,
                                 presentingWidth: presentingWidth)
        }
        if let sheet = hostingController.sheetPresentationController {
            configureSheetDetents(sheet,
                                 hostingController: hostingController,
                                 presentingWidth: presentingWidth)
        }
    }
    
    private func configurePopoverSource(_ popover: UIPopoverPresentationController, source: AnyObject, sourceRect: CGRect) {
        if let source = source as? UIView {
            popover.sourceView = source
            popover.sourceRect = sourceRect
        } else if let source = source as? UIBarButtonItem {
            popover.barButtonItem = source
        }
    }
    
    private func configureSheetDetents<Content: View>(_ sheet: UISheetPresentationController,
                                                      hostingController: UIHostingController<Content>,
                                                      presentingWidth: CGFloat) {
        if #available(iOS 16.0, *) {
            let contentHeight = calculateContentHeight(for: hostingController, width: presentingWidth)
            sheet.detents = [.custom { context in
                let maxHeight = context.maximumDetentValue * Constants.maxHeightRatio
                return min(contentHeight, maxHeight)
            }]
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        } else {
            sheet.detents = [.medium()]
        }
        sheet.prefersGrabberVisible = false
        if #unavailable(iOS 26) {
            sheet.preferredCornerRadius = MainActor.assumeIsolated { SheetMetrics.cornerRadius }
        }
    }
    
    private func calculateSheetHeight<Content: View>(for hostingController: UIHostingController<Content>,
                                                     width: CGFloat,
                                                     maxHeight: CGFloat? = nil) -> CGFloat {
        if #available(iOS 16.0, *) {
            let contentHeight = calculateContentHeight(for: hostingController, width: width)
            if let maxHeight = maxHeight {
                return min(contentHeight, maxHeight)
            }
            return contentHeight
        } else {
            return Constants.iPadSheetDefaultHeight
        }
    }
    
    @available(iOS 16.0, *)
    private func calculateContentHeight<Content: View>(for hostingController: UIHostingController<Content>,
                                                       width: CGFloat) -> CGFloat {
        let sizingController = UIHostingController(rootView: hostingController.rootView)
        sizingController.disableSafeArea()
        let targetSize = sizingController.sizeThatFits(in: CGSize(width: width, height: .infinity))
        return targetSize.height
    }
    
}

private extension FireConfirmationPresenter {
    enum Constants {
        static let iPadSheetWidth: CGFloat = 375
        static let iPadSheetDefaultHeight: CGFloat = 520
        static let maxHeightRatio: CGFloat = 0.9
    }
}
