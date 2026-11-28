//
//  RMFSheetViewController.swift
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
import MetricBuilder

/// Presents `RMFSheetView` as a page sheet on iPhone and a form sheet on iPad, sized by the content's height.
/// Every action dismisses the sheet and is reported once it's gone, so the caller can present what comes next;
/// swiping it away reports `.close`.
final class RMFSheetViewController: UIHostingController<RMFSheetView>, UIAdaptivePresentationControllerDelegate {

    static let formSheetWidth: CGFloat = 540
    static let contentDetentIdentifier = UISheetPresentationController.Detent.Identifier("rmfSheetContent")

    private let height: RMFSheetContent.Height
    private let onAction: (RMFSheetAction) -> Void

    init(content: RMFSheetContent, onAction: @escaping (RMFSheetAction) -> Void) {
        self.height = content.height
        self.onAction = onAction
        var dismissSheet: (RMFSheetAction) -> Void = { _ in }
        super.init(rootView: RMFSheetView(content: content) { action in dismissSheet(action) })
        dismissSheet = { [weak self] action in
            self?.dismiss(animated: true) { onAction(action) }
        }

        modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .formSheet : .pageSheet
        presentationController?.delegate = self
        configureDetents()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let isFormSheet = modalPresentationStyle == .formSheet
            && presentingViewController?.traitCollection.horizontalSizeClass == .regular
        let layout: RMFSheetView.Layout = isFormSheet ? .formSheet : .phone
        if rootView.layout != layout {
            rootView.layout = layout
        }
        guard isFormSheet else { return }
        // A regular-width form sheet ignores detents.
        let preferredHeight = height == .full ? .greatestFiniteMagnitude : fittingHeight(width: Self.formSheetWidth)
        let size = CGSize(width: Self.formSheetWidth, height: preferredHeight)
        if preferredContentSize != size {
            preferredContentSize = size
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onAction(.close)
    }

    private func configureDetents() {
        guard let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = false
        sheet.preferredCornerRadius = MainActor.assumeIsolated { SheetMetrics.cornerRadius }

        switch height {
        case .full:
            sheet.detents = [.large()]
        case .content:
            if #available(iOS 16, *) {
                sheet.detents = [.custom(identifier: Self.contentDetentIdentifier) { [weak self] context in
                    guard let self, let width = self.sheetWidth else { return nil }
                    // Detent heights exclude the bottom safe area; the fitting height includes it.
                    let height = self.fittingHeight(width: width) - self.view.safeAreaInsets.bottom
                    return min(height, context.maximumDetentValue)
                }]
            } else {
                sheet.detents = [.medium()]
            }
        }
    }

    /// Before its first layout the sheet has no width, so fall back to the presenter's.
    private var sheetWidth: CGFloat? {
        [view.bounds.width, presentingViewController?.view.bounds.width ?? 0].first { $0 > 0 }
    }

    private func fittingHeight(width: CGFloat) -> CGFloat {
        sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }
}
