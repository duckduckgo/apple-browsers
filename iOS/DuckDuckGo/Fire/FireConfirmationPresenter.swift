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
import PrivacyConfig
import Common
import Core
import AIChat
import Persistence

struct FireConfirmationPresenter {
    
    let tabsModel: TabsModelProtocol
    let featureFlagger: FeatureFlagger
    let historyManager: HistoryManaging
    let fireproofing: Fireproofing
    let aiChatSettings: AIChatSettingsProvider
    let keyValueFilesStore: ThrowingKeyValueStoring
    
    @MainActor
    func presentFireConfirmation(on viewController: UIViewController,
                                 attachPopoverTo source: AnyObject,
                                 tabViewModel: TabViewModel?,
                                 daxDialogsManager: DaxDialogsManaging,
                                 onConfirm: @escaping (FireRequest) -> Void,
                                 onCancel: @escaping () -> Void) {
        let sourceRect = (source as? UIView)?.bounds ?? .zero
        if featureFlagger.isFeatureOn(.burnSingleTab) {
            presentScopeConfirmationSheet(on: viewController, from: source, sourceRect: sourceRect, tabViewModel: tabViewModel, daxDialogsManager: daxDialogsManager, onConfirm: onConfirm, onCancel: onCancel)
        } else {
            presentLegacyConfirmationAlert(on: viewController, from: source, sourceRect: sourceRect, onConfirm: onConfirm, onCancel: onCancel)
        }
    }
    
    @MainActor
    func presentFireConfirmation(on viewController: UIViewController,
                                 sourceRect: CGRect,
                                 tabViewModel: TabViewModel?,
                                 daxDialogsManager: DaxDialogsManaging,
                                 onConfirm: @escaping (FireRequest) -> Void,
                                 onCancel: @escaping () -> Void) {
        guard let window = UIApplication.shared.firstKeyWindow else {
            assertionFailure("No key window available")
            return
        }
        if featureFlagger.isFeatureOn(.burnSingleTab) {
            presentScopeConfirmationSheet(on: viewController, from: window, sourceRect: sourceRect, tabViewModel: tabViewModel, daxDialogsManager: daxDialogsManager, onConfirm: onConfirm, onCancel: onCancel)
        } else {
            presentLegacyConfirmationAlert(on: viewController, from: window, sourceRect: sourceRect, onConfirm: onConfirm, onCancel: onCancel)
        }
    }
    
    // MARK: - Scope-based Confirmation (burnSingleTab feature flag)
    
    @MainActor
        private func presentScopeConfirmationSheet(on viewController: UIViewController,
                                                   from source: AnyObject,
                                                   sourceRect: CGRect,
                                                   tabViewModel: TabViewModel?,
                                                   daxDialogsManager: DaxDialogsManaging,
                                                   onConfirm: @escaping (FireRequest) -> Void,
                                                   onCancel: @escaping () -> Void) {
            let viewModel = ScopedFireConfirmationViewModel(tabViewModel: tabViewModel,
                                                            daxDialogsManager: daxDialogsManager,
                onConfirm: { [weak viewController] fireOptions in
                    viewController?.dismiss(animated: true) {
                        onConfirm(fireOptions)
                    }
                },
                onCancel: { [weak viewController] in
                    viewController?.dismiss(animated: true) {
                        onCancel()
                    }
                }
            )
            
            let confirmationView = ScopedFireConfirmationView(viewModel: viewModel)
            let hostingController = makeHostingController(with: confirmationView)
            let presentingWidth = viewController.view.frame.width
            configurePresentation(for: hostingController,
                                  source: source,
                                  sourceRect: sourceRect,
                                  presentingWidth: presentingWidth)
            viewController.present(hostingController, animated: true)
        }
    
    // MARK: - Granular Confirmation (legacy, currently unused)
    
    /// Presents a SwiftUI-based confirmation sheet as an alternative UI for the "Fire" action.
    /// 
    /// This function builds a GranularFireConfirmationView hosted in a UIHostingController and presents it
    /// as either a sheet or popover, depending on the device. Currently, this function is unused but
    /// demonstrates an alternate UI flow for fire confirmation.
    @MainActor
    private func presentGranularConfirmationSheet(on viewController: UIViewController,
                                                  from source: AnyObject,
                                                  sourceRect: CGRect,
                                                  onConfirm: @escaping (FireRequest) -> Void,
                                                  onCancel: @escaping () -> Void) {
        let viewModel = makeViewModel(dismissing: viewController,
                                      onConfirm: onConfirm,
                                      onCancel: onCancel)
        let confirmationView = GranularFireConfirmationView(viewModel: viewModel)
        let hostingController = makeHostingController(with: confirmationView)
        let presentingWidth = viewController.view.frame.width
        
        configurePresentation(for: hostingController,
                              source: source,
                              sourceRect: sourceRect,
                              presentingWidth: presentingWidth)
        
        viewController.present(hostingController, animated: true)
    }
    
    @MainActor
    private func makeViewModel(dismissing viewController: UIViewController,
                               onConfirm: @escaping (FireRequest) -> Void,
                               onCancel: @escaping () -> Void) -> GranularFireConfirmationViewModel {
        GranularFireConfirmationViewModel(
            tabsModel: tabsModel,
            historyManager: historyManager,
            fireproofing: fireproofing,
            aiChatSettings: aiChatSettings,
            keyValueFilesStore: keyValueFilesStore,
            onConfirm: { [weak viewController] fireOptions in
                viewController?.dismiss(animated: true) {
                    onConfirm(fireOptions)
                }
            },
            onCancel: { [weak viewController] in
                viewController?.dismiss(animated: true) {
                    onCancel()
                }
            }
        )
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
            sheet.detents = [.large()]
        }
        sheet.prefersGrabberVisible = false
        sheet.preferredCornerRadius = Constants.sheetCornerRadius
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
    
    private func presentLegacyConfirmationAlert(on viewController: UIViewController,
                                                from source: AnyObject,
                                                sourceRect: CGRect,
                                                onConfirm: @escaping (FireRequest) -> Void,
                                                onCancel: @escaping () -> Void) {
        
        let alert = ForgetDataAlert.buildAlert(cancelHandler: {
            onCancel()
        }, forgetTabsAndDataHandler: {
            let request = FireRequest(options: .all, trigger: .manualFire, scope: .all)
            onConfirm(request)
        })
        if let view = source as? UIView {
            if let popover = alert.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = sourceRect
            }
            viewController.present(alert, animated: true)
        } else if let button = source as? UIBarButtonItem {
            viewController.present(controller: alert, fromButtonItem: button)
        } else {
            assertionFailure("Unexpected sender")
        }
    }
}

private extension FireConfirmationPresenter {
    enum Constants {
        static let iPadSheetWidth: CGFloat = 375
        static let iPadSheetDefaultHeight: CGFloat = 520
        static let sheetCornerRadius: CGFloat = 24
        static let maxHeightRatio: CGFloat = 0.9
    }
}
