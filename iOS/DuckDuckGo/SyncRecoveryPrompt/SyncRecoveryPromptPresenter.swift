//
//  SyncRecoveryPromptPresenter.swift
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

import UIKit
import SwiftUI
import Core

@MainActor
protocol SyncRecoveryPromptPresenting: AnyObject {
    func presentSyncRecoveryPrompt(from viewController: UIViewController,
                                   onSyncFlowSelected: @escaping (String) -> Void)
}

@MainActor
final class SyncRecoveryPromptPresenter: NSObject, SyncRecoveryPromptPresenting {
    
    func presentSyncRecoveryPrompt(from viewController: UIViewController,
                                   onSyncFlowSelected: @escaping (String) -> Void) {
        let promptController = UIHostingController(
            rootView: SyncRecoveryPromptView(
                onSyncWithAnotherDevice: {},
                onShowAlternatives: {},
                onCancel: {}
            )
        )
        
        promptController.rootView = SyncRecoveryPromptView(
            onSyncWithAnotherDevice: { [weak viewController] in
                viewController?.dismiss(animated: true) {
                    onSyncFlowSelected(SyncSettingsViewController.Constants.startSyncFlow)
                }
            },
            onShowAlternatives: { [weak self, weak promptController, weak viewController] in
                promptController?.dismiss(animated: true) {
                    guard let presentingViewController = viewController else { return }
                    self?.presentAlternativePrompt(from: presentingViewController,
                                                   onSyncFlowSelected: onSyncFlowSelected)
                }
            },
            onCancel: { [weak viewController] in
                viewController?.dismiss(animated: true)
            }
        )
        
        configureModalPresentation(for: promptController)
        viewController.present(promptController, animated: true)
    }
    
    private func presentAlternativePrompt(from viewController: UIViewController,
                                           onSyncFlowSelected: @escaping (String) -> Void) {
        let alternativeController = UIHostingController(
            rootView: SyncRecoveryAlternativeView(
                onSyncFlowSelected: { _ in },
                onCancel: { }
            )
        )
        
        alternativeController.rootView = SyncRecoveryAlternativeView(
            onSyncFlowSelected: { [weak viewController] flowType in
                viewController?.dismiss(animated: true) {
                    onSyncFlowSelected(flowType)
                }
            },
            onCancel: { [weak alternativeController] in
                alternativeController?.dismiss(animated: true)
            }
        )
        
        configureModalPresentation(for: alternativeController)
        viewController.present(alternativeController, animated: true)
    }
    
    private func configureModalPresentation(for hostingController: UIHostingController<some View>) {
        hostingController.modalPresentationStyle = .automatic
        hostingController.modalTransitionStyle = .coverVertical
    }
}
