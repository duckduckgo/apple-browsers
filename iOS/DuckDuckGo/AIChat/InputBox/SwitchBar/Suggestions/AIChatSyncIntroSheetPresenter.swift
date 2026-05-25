//
//  AIChatSyncIntroSheetPresenter.swift
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

import SwiftUI
import UIKit

protocol AIChatSyncIntroSheetPresenting {
    @MainActor
    func present(from viewController: UIViewController, onSyncSetupRequested: @escaping () -> Void)
}

final class AIChatSyncIntroSheetPresenter: AIChatSyncIntroSheetPresenting {

    @MainActor
    func present(from viewController: UIViewController, onSyncSetupRequested: @escaping () -> Void) {
        let sheet = AIChatSyncIntroSheetView(
            onScanTap: { [weak viewController] in
                viewController?.dismiss(animated: true, completion: onSyncSetupRequested)
            },
            onNotNowTap: { [weak viewController] in
                viewController?.dismiss(animated: true)
            }
        )
        let hostingController = UIHostingController(rootView: sheet)
        hostingController.view.backgroundColor = UIColor(designSystemColor: .backgroundSheets)
        if #available(iOS 16.4, *) {
            hostingController.sizingOptions = .intrinsicContentSize
        }
        if let presentation = hostingController.sheetPresentationController {
            if #available(iOS 16.0, *) {
                let fittingSize = hostingController.view.systemLayoutSizeFitting(
                    CGSize(width: UIScreen.main.bounds.width, height: UIView.layoutFittingCompressedSize.height)
                )
                presentation.detents = [.custom { _ in fittingSize.height }]
            } else {
                presentation.detents = [.medium()]
            }
            presentation.prefersGrabberVisible = true
        }
        viewController.present(hostingController, animated: true)
    }
}
