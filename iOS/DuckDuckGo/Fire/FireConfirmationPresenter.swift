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
import BrowserServicesKit
import Common

struct FireConfirmationPresenter {
    
    let featureFlagger: FeatureFlagger
    
    func presentFireConfirmation(on viewController: UIViewController,
                                 from source: AnyObject,
                                 onConfirm: @escaping () -> Void,
                                 onCancel: @escaping () -> Void) {
        guard featureFlagger.isFeatureOn(.granularFireButtonOptions) else {
            presentLegacyConfirmationAlert(on: viewController, from: source, onConfirm: onConfirm, onCancel: onCancel)
            return
        }
        let viewModel = FireConfirmationViewModel(
            onConfirm: { [weak viewController] in
                viewController?.dismiss(animated: true) {
                    onConfirm()
                }
            },
            onCancel: { [weak viewController] in
                viewController?.dismiss(animated: true) {
                    onCancel()
                }
            }
        )
        
        let confirmationView = FireConfirmationView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: confirmationView)
        
        hostingController.modalTransitionStyle = .coverVertical
                
        if DevicePlatform.isIpad, let source = source as? UIView {
            configureIPadPopoverPresentation(for: hostingController, from: source)
        } else {
            configureSheetPresentation(for: hostingController,
                                       presentingWidth: viewController.view.frame.width)
        }
        viewController.present(hostingController, animated: true)
    }
    
    private func configureSheetPresentation(for hostingController: UIHostingController<FireConfirmationView>,
                                            presentingWidth: CGFloat) {
        hostingController.modalPresentationStyle = .pageSheet
        guard let sheet = hostingController.sheetPresentationController else { return }
        
        if #available(iOS 16.0, *) {
            let targetHeight = calculateContentHeight(for: hostingController.rootView, width: presentingWidth)
            sheet.detents = [.custom { _ in targetHeight }]
        } else {
            sheet.detents = [.large()]
        }
        sheet.prefersGrabberVisible = false
        sheet.preferredCornerRadius = Constants.sheetCornerRadius
    }
    
    private func configureIPadPopoverPresentation(for hostingController: UIHostingController<FireConfirmationView>,
                                                  from source: UIView) {
        hostingController.modalPresentationStyle = .popover
        hostingController.popoverPresentationController?.sourceView = source
        hostingController.popoverPresentationController?.sourceRect = source.bounds
        let sheetHeight: CGFloat
        if #available(iOS 16.0, *) {
            sheetHeight = calculateContentHeight(for: hostingController.rootView, width: Constants.iPadSheetWidth)
        } else {
            sheetHeight = Constants.iPadSheetDefaultHeight
        }
        hostingController.preferredContentSize = CGSize(width: Constants.iPadSheetWidth, height: sheetHeight)
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
                                                onConfirm: @escaping () -> Void,
                                                onCancel: @escaping () -> Void) {
        
        let alert = ForgetDataAlert.buildAlert(cancelHandler: {
            onCancel()
        }, forgetTabsAndDataHandler: {
            onConfirm()
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
        static let sheetCornerRadius: CGFloat = 12
    }
}
