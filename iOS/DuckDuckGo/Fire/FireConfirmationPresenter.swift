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
                                 isSingleTab: Bool = false,
                                 browsingMode: BrowsingMode,
                                 onConfirm: @escaping (FireRequest) -> Void,
                                 onCancel: @escaping () -> Void) {
        let sourceRect = (source as? UIView)?.bounds ?? .zero
        presentScopeConfirmationSheet(on: viewController, from: source, sourceRect: sourceRect, tabViewModel: tabViewModel, pixelSource: pixelSource, fireContext: fireContext, isSingleTab: isSingleTab, browsingMode: browsingMode, onConfirm: onConfirm, onCancel: onCancel)
    }

    @MainActor
    func presentFireConfirmation(on viewController: UIViewController,
                                 sourceRect: CGRect,
                                 tabViewModel: TabViewModel?,
                                 pixelSource: FireRequest.Source,
                                 fireContext: ScopedFireConfirmationViewModel.FireContext,
                                 isSingleTab: Bool = false,
                                 browsingMode: BrowsingMode,
                                 onConfirm: @escaping (FireRequest) -> Void,
                                 onCancel: @escaping () -> Void) {
        guard let window = UIApplication.shared.firstKeyWindow else {
            assertionFailure("No key window available")
            return
        }
        presentScopeConfirmationSheet(on: viewController, from: window, sourceRect: sourceRect, tabViewModel: tabViewModel, pixelSource: pixelSource, fireContext: fireContext, isSingleTab: isSingleTab, browsingMode: browsingMode, onConfirm: onConfirm, onCancel: onCancel)
    }

    // MARK: - Scope-based Confirmation

    @MainActor
    private func presentScopeConfirmationSheet(on viewController: UIViewController,
                                               from source: AnyObject,
                                               sourceRect: CGRect,
                                               tabViewModel: TabViewModel?,
                                               pixelSource: FireRequest.Source,
                                               fireContext: ScopedFireConfirmationViewModel.FireContext,
                                               isSingleTab: Bool,
                                               browsingMode: BrowsingMode,
                                               onConfirm: @escaping (FireRequest) -> Void,
                                               onCancel: @escaping () -> Void) {
        let viewModel = ScopedFireConfirmationViewModel(tabViewModel: tabViewModel,
                                                        source: pixelSource,
                                                        fireContext: fireContext,
                                                        isSingleTab: isSingleTab,
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

        // Capture the presenting context's true size class; it's reset to `.compact` inside the popover container.
        let presentationSizeClass = UserInterfaceSizeClass(viewController.traitCollection.horizontalSizeClass)
        let confirmationView = ScopedFireConfirmationView(viewModel: viewModel)
            .environment(\.presentationHorizontalSizeClass, presentationSizeClass)
        let hostingController = makeHostingController(with: confirmationView)
        // Prevent swipe-to-dismiss for the experiment flow: the user must make an
        // explicit choice (fire or cancel) to keep the locked-controls state consistent.
        if case .duckAIOnboarding = fireContext {
            hostingController.isModalInPresentation = true
        }

        let limitsLandscapeWidth = !DevicePlatform.isIpad && AppDependencyProvider.shared.featureFlagger.isFeatureOn(.swipeToDelete)
        let presentingSize = limitsLandscapeWidth
            ? (viewController.view.window?.bounds.size ?? viewController.view.bounds.size)
            : viewController.view.frame.size
        configurePresentation(for: hostingController,
                              source: source,
                              sourceRect: sourceRect,
                              presentingSize: presentingSize,
                              limitsLandscapeWidth: limitsLandscapeWidth)
        if limitsLandscapeWidth {
            hostingController.onPresentingSizeChange = { [weak hostingController] size in
                guard let hostingController else { return }
                configurePresentation(for: hostingController,
                                      source: source,
                                      sourceRect: sourceRect,
                                      presentingSize: size,
                                      limitsLandscapeWidth: true)
            }
        }
        viewController.present(hostingController, animated: true)
    }
    
    // MARK: - Shared Presentation Helpers
        
    private func makeHostingController<Content: View>(with view: Content) -> FireConfirmationHostingController<Content> {
        let hostingController = FireConfirmationHostingController(rootView: view)
        hostingController.view.backgroundColor = UIColor(designSystemColor: .backgroundTertiary)
        hostingController.modalTransitionStyle = .coverVertical
        hostingController.modalPresentationStyle = DevicePlatform.isIpad ? .popover : .pageSheet
        return hostingController
    }
    
    private func configurePresentation<Content: View>(for hostingController: UIHostingController<Content>,
                                                      source: AnyObject,
                                                      sourceRect: CGRect,
                                                      presentingSize: CGSize,
                                                      limitsLandscapeWidth: Bool) {
        let landscapeWidth = limitsLandscapeWidth && presentingSize.width > presentingSize.height
            ? presentingSize.height : nil
        let contentWidth = landscapeWidth ?? presentingSize.width
        if let popoverController = hostingController.popoverPresentationController {
            configurePopoverSource(popoverController, source: source, sourceRect: sourceRect)
            
            let width = landscapeWidth ?? Constants.iPadSheetWidth
            let sheetHeight = calculateSheetHeight(for: hostingController, width: width)
            hostingController.preferredContentSize = CGSize(width: width, height: sheetHeight)

            if #available(iOS 16.4, *) {
                /// Keyboard Safe Area Insets are interfering may interfere when presented as a popover
                hostingController.safeAreaRegions = [.container]
            }

            configureSheetDetents(popoverController.adaptiveSheetPresentationController,
                                 hostingController: hostingController,
                                 presentingWidth: contentWidth,
                                 limitsLandscapeWidth: limitsLandscapeWidth)
        }
        if let sheet = hostingController.sheetPresentationController {
            if limitsLandscapeWidth && hostingController.popoverPresentationController == nil {
                if #available(iOS 17.0, *) {
                    sheet.prefersPageSizing = landscapeWidth == nil
                }
                hostingController.preferredContentSize = landscapeWidth.map {
                    CGSize(width: $0, height: calculateSheetHeight(for: hostingController, width: $0))
                } ?? .zero
            }
            configureSheetDetents(sheet,
                                 hostingController: hostingController,
                                 presentingWidth: contentWidth,
                                 limitsLandscapeWidth: limitsLandscapeWidth)
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
                                                      presentingWidth: CGFloat,
                                                      limitsLandscapeWidth: Bool) {
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
            if limitsLandscapeWidth {
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            }
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

private final class FireConfirmationHostingController<Content: View>: UIHostingController<Content> {
    var onPresentingSizeChange: ((CGSize) -> Void)?
    private var lastPresentingSize: CGSize?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePresentingSize()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updatePresentingSize()
        }
    }

    private func updatePresentingSize() {
        guard let view = presentingViewController?.view else { return }
        let size = view.window?.bounds.size ?? view.bounds.size
        guard size != lastPresentingSize else { return }
        lastPresentingSize = size
        onPresentingSizeChange?(size)
    }
}

private extension FireConfirmationPresenter {
    enum Constants {
        static let iPadSheetWidth: CGFloat = 375
        static let iPadSheetDefaultHeight: CGFloat = 520
        static let maxHeightRatio: CGFloat = 0.9
    }
}
