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
                                 onConfirm: @escaping (FireOptions) -> Void,
                                 onCancel: @escaping () -> Void) {
        guard featureFlagger.isFeatureOn(.granularFireButtonOptions) else {
            presentLegacyConfirmationAlert(on: viewController, from: source, onConfirm: onConfirm, onCancel: onCancel)
            return
        }
        
        let viewModel = makeViewModel(dismissing: viewController,
                                      onConfirm: onConfirm,
                                      onCancel: onCancel)
        let hostingController = makeHostingController(with: viewModel)
        let presentingWidth = viewController.view.frame.width
        
        configurePresentation(for: hostingController,
                             source: source,
                             presentingWidth: presentingWidth)
        
        viewController.present(hostingController, animated: true)
    }
    
    @MainActor
    private func makeViewModel(dismissing viewController: UIViewController,
                               onConfirm: @escaping (FireOptions) -> Void,
                               onCancel: @escaping () -> Void) -> FireConfirmationViewModel {
        FireConfirmationViewModel(
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
    
    private func makeHostingController(with viewModel: FireConfirmationViewModel) -> UIHostingController<FireConfirmationView> {
        let confirmationView = FireConfirmationView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: confirmationView)
        hostingController.view.backgroundColor = UIColor(designSystemColor: .backgroundTertiary)
        hostingController.modalTransitionStyle = .coverVertical
        hostingController.modalPresentationStyle = DevicePlatform.isIpad ? .popover : .pageSheet
        return hostingController
    }
    
    private func configurePresentation(for hostingController: UIHostingController<FireConfirmationView>,
                                       source: AnyObject,
                                       presentingWidth: CGFloat) {
        if let popoverController = hostingController.popoverPresentationController {
            configurePopoverSource(popoverController, source: source)
            
            let sheetHeight = calculateSheetHeight(for: hostingController.rootView,
                                                   width: Constants.iPadSheetWidth)
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
    
    private func configurePopoverSource(_ popover: UIPopoverPresentationController, source: AnyObject) {
        if let source = source as? UIView {
            popover.sourceView = source
            popover.sourceRect = source.bounds
        } else if let source = source as? UIBarButtonItem {
            popover.barButtonItem = source
        }
    }
    
    private func configureSheetDetents(_ sheet: UISheetPresentationController,
                                       hostingController: UIHostingController<FireConfirmationView>,
                                       presentingWidth: CGFloat) {
        if #available(iOS 16.0, *) {
            let contentHeight = calculateContentHeight(for: hostingController.rootView,
                                                       width: presentingWidth)
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
    
    private func calculateSheetHeight(for view: FireConfirmationView, width: CGFloat, maxHeight: CGFloat? = nil) -> CGFloat {
        if #available(iOS 16.0, *) {
            let contentHeight = calculateContentHeight(for: view, width: width)
            if let maxHeight = maxHeight {
                return min(contentHeight, maxHeight)
            }
            return contentHeight
        } else {
            return Constants.iPadSheetDefaultHeight
        }
    }
    
    @available(iOS 16.0, *)
    private func calculateContentHeight(for view: FireConfirmationView, width: CGFloat) -> CGFloat {
        let sizingController = UIHostingController(rootView: view)
        sizingController.disableSafeArea()
        let targetSize = sizingController.sizeThatFits(in: CGSize(width: width, height: .infinity))
        return targetSize.height
    }
    
    private func presentLegacyConfirmationAlert(on viewController: UIViewController,
                                                from source: AnyObject,
                                                onConfirm: @escaping (FireOptions) -> Void,
                                                onCancel: @escaping () -> Void) {
        
        let alert = ForgetDataAlert.buildAlert(cancelHandler: {
            onCancel()
        }, forgetTabsAndDataHandler: {
            onConfirm(.all)
        })
        if let view = source as? UIView {
            viewController.present(controller: alert, fromView: view)
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
