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
import PixelKit

@MainActor
protocol SyncRecoveryPromptPresenting: AnyObject {
    func presentSyncRecoveryPrompt(from viewController: UIViewController,
                                   onSyncFlowSelected: @escaping (String) -> Void)
}

// MARK: - Custom Hosting Controllers for Orientation Control

final class SyncRecoveryPromptHostingController: UIHostingController<SyncRecoveryPromptView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return .portrait
    }
}

final class SyncRecoveryAlternativeHostingController: UIHostingController<SyncRecoveryAlternativeView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return .portrait
    }
}

@MainActor
final class SyncRecoveryPromptPresenter: NSObject, SyncRecoveryPromptPresenting {
    
    func presentSyncRecoveryPrompt(from viewController: UIViewController,
                                   onSyncFlowSelected: @escaping (String) -> Void) {
        let promptController = SyncRecoveryPromptHostingController(
            rootView: SyncRecoveryPromptView(
                onSyncWithAnotherDevice: { [weak viewController] in
                    Pixel.fire(pixel: .syncRecoveryPromptSyncWithAnotherDeviceTapped)
                    viewController?.dismiss(animated: true) {
                        onSyncFlowSelected(SyncSettingsViewController.Constants.startSyncFlow)
                    }
                },
                onShowAlternatives: { [weak self, weak viewController] in
                    Pixel.fire(pixel: .syncRecoveryPromptShowAlternativesTapped)
                    viewController?.dismiss(animated: true) {
                        guard let presentingViewController = viewController else { return }
                        self?.presentAlternativePrompt(from: presentingViewController,
                                                       onSyncFlowSelected: onSyncFlowSelected)
                    }
                },
                onCancel: { [weak viewController] in
                    Pixel.fire(pixel: .syncRecoveryPromptDismissed)
                    viewController?.dismiss(animated: true)
                }
            )
        )

        configureModalPresentation(for: promptController)
        viewController.present(promptController, animated: true) {
            Pixel.fire(pixel: .syncRecoveryPromptDisplayed)
        }
    }
    
    private func presentAlternativePrompt(from viewController: UIViewController,
                                          onSyncFlowSelected: @escaping (String) -> Void) {
        let alternativeController = SyncRecoveryAlternativeHostingController(
            rootView: SyncRecoveryAlternativeView(
                onSyncFlowSelected: { [weak viewController] flowType in
                    // Fire appropriate pixel based on which button was tapped
                    if flowType == SyncSettingsViewController.Constants.startSyncFlow {
                        Pixel.fire(pixel: .syncRecoveryAlternativeScanRecoveryCodeTapped)
                    } else {
                        Pixel.fire(pixel: .syncRecoveryAlternativeBackupThisDeviceTapped)
                    }
                    viewController?.dismiss(animated: true) {
                        onSyncFlowSelected(flowType)
                    }
                },
                onCancel: { [weak viewController] in
                    Pixel.fire(pixel: .syncRecoveryAlternativeDismissed)
                    viewController?.dismiss(animated: true)
                }
            )
        )

        configureModalPresentation(for: alternativeController)
        viewController.present(alternativeController, animated: true) {
            Pixel.fire(pixel: .syncRecoveryAlternativeDisplayed)
        }
    }
    
    private func configureModalPresentation(for hostingController: UIHostingController<some View>) {
        hostingController.modalPresentationStyle = .automatic
        hostingController.modalTransitionStyle = .coverVertical
    }
}
