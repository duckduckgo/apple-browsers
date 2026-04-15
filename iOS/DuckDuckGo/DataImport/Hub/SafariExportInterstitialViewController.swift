//
//  SafariExportInterstitialViewController.swift
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
import SwiftUI
import DesignResourcesKit

final class SafariExportInterstitialViewController: UIViewController {

    var onRequestExport: (() -> Void)?
    private var contentHeight: CGFloat = 420

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(designSystemColor: .background)
        setupView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateSheetHeight(contentHeight)
    }

    private func setupView() {
        let interstitialView = SafariExportInterstitialView(
            onOpenSettingsToExport: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.onRequestExport?()
                }
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            },
            onContentHeightChange: { [weak self] contentHeight in
                self?.updateSheetHeight(contentHeight)
            }
        )
        let hostingController = UIHostingController(rootView: interstitialView)
        hostingController.view.backgroundColor = UIColor(designSystemColor: .background)
        hostingController.view.isOpaque = true
        installChildViewController(hostingController)
    }

    private func updateSheetHeight(_ nextHeight: CGFloat) {
        guard #available(iOS 16.0, *) else { return }

        let boundedHeight = max(360, nextHeight)
        guard abs(boundedHeight - contentHeight) > 0.5 || (presentationController as? UISheetPresentationController)?.detents.isEmpty == true else {
            return
        }

        contentHeight = boundedHeight

        if let sheetPresentationController = presentationController as? UISheetPresentationController {
            sheetPresentationController.animateChanges {
                sheetPresentationController.detents = [.custom(resolver: { _ in boundedHeight })]
            }
        }
    }
}
