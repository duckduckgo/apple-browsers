//
//  AddFavoriteViewController.swift
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

import DesignResourcesKit
import SwiftUI
import UIKit

final class AddFavoriteViewController: UIHostingController<AddFavoriteView> {
    private var measuredLayout: (width: CGFloat, contentSize: UIContentSizeCategory)?

    init(model: AddFavoriteViewModel) {
        var onClose: (() -> Void)?
        super.init(rootView: AddFavoriteView(model: model, onClose: { onClose?() }))
        onClose = { [weak self] in self?.dismiss(animated: true) }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 26, *) {
            // Let the system sheet supply one continuous glass surface, including its insets.
            view.backgroundColor = .clear
        } else {
            view.backgroundColor = UIColor(designSystemColor: .background)
        }
        updateContentSize()
        if let sheet = sheetPresentationController {
            if #available(iOS 16, *) {
                sheet.detents = [.custom { [weak self] context in
                    guard let self else { return nil }
                    return min(self.preferredContentSize.height, context.maximumDetentValue)
                }]
            } else {
                sheet.detents = [.medium()]
            }
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = Metrics.sheetCornerRadius
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateContentSize()
    }

    private func updateContentSize() {
        let width = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right
        guard width > 0 else { return }
        // Layout passes repeat for keyboard and detent changes. Re-measure only when the inputs change.
        let layout = (width: width, contentSize: traitCollection.preferredContentSizeCategory)
        if let measuredLayout, measuredLayout == layout { return }
        measuredLayout = layout
        // Measure the form rather than its scroll viewport, excluding keyboard and sheet insets.
        let sizingController = UIHostingController(rootView: rootView.form)
        if #available(iOS 16.4, *) {
            sizingController.safeAreaRegions = []
        }
        let height = ceil(sizingController.sizeThatFits(in: CGSize(width: width, height: .infinity)).height)
        guard preferredContentSize.height != height else { return }
        preferredContentSize.height = height
        if #available(iOS 16, *) {
            sheetPresentationController?.invalidateDetents()
        }
    }
}

private enum Metrics {
    static let sheetCornerRadius: CGFloat = 48
}
