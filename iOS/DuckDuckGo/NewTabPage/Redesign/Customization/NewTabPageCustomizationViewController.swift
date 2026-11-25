//
//  NewTabPageCustomizationViewController.swift
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

final class NewTabPageCustomizationViewController: UIHostingController<NewTabPageCustomizationView> {

    var onAllSettingsSelected: (() -> Void)?

    private let model: NewTabPageCustomizationModel

    init(model: NewTabPageCustomizationModel) {
        self.model = model

        var onClose: (() -> Void)?
        super.init(rootView: NewTabPageCustomizationView(model: model, onClose: { onClose?() }))

        onClose = { [weak self] in
            self?.dismiss(animated: true)
        }

        model.onAllSettingsSelected = { [weak self] in
            guard let self else { return }
            // Dismiss first, so settings replace this sheet rather than stacking on top of it.
            dismiss(animated: true) {
                self.onAllSettingsSelected?()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private enum Metrics {
        static let bottomPadding: CGFloat = 16
    }

    private var fittingContentHeight: CGFloat?

    override func viewDidLoad() {
        super.viewDidLoad()

        if let sheet = sheetPresentationController {
            if #available(iOS 16, *) {
                let fittingDetent = UISheetPresentationController.Detent.custom(identifier: .init("fittingContent")) { [weak self] context in
                    guard let fittingContentHeight = self?.fittingContentHeight else { return context.maximumDetentValue }
                    return min(fittingContentHeight, context.maximumDetentValue)
                }
                sheet.detents = [fittingDetent]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFittingContentHeight()
    }

    /// Reads the list's laid out height, since a SwiftUI `List` reports no intrinsic height of its own.
    private func updateFittingContentHeight() {
        // Depends on `List` being backed by a collection view. If that changes, no height is set and the sheet opens full height.
        guard let collectionView = view.firstDescendant(ofType: UICollectionView.self) else { return }
        let contentBounds = CGRect(origin: .zero, size: collectionView.collectionViewLayout.collectionViewContentSize)
        let lastRowBottom = collectionView.collectionViewLayout.layoutAttributesForElements(in: contentBounds)?
            .filter { $0.representedElementCategory == .cell }
            .map(\.frame.maxY)
            .max()
        guard let lastRowBottom else { return }
        // The bounds origin is the scroll offset, so converting it yields the list's frame top, unaffected by scrolling.
        let listTop = collectionView.convert(collectionView.bounds.origin, to: view).y
        let height = ceil(listTop + collectionView.adjustedContentInset.top + lastRowBottom + Metrics.bottomPadding)
        guard abs(height - (fittingContentHeight ?? 0)) > 0.5 else { return }
        fittingContentHeight = height
        if #available(iOS 16, *) {
            sheetPresentationController?.invalidateDetents()
        }
    }
}

private extension UIView {

    func firstDescendant<T: UIView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}
