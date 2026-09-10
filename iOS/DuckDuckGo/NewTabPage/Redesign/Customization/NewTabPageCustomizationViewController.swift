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

/// Hosts the "Customize Your Start" sheet.
final class NewTabPageCustomizationViewController: UIHostingController<NewTabPageCustomizationView> {

    /// Asks the presenter to open the app's settings. Raised here rather than presented directly,
    /// so settings replace this sheet instead of stacking on top of it.
    var onAllSettingsSelected: (() -> Void)?

    private let model: NewTabPageCustomizationModel

    init(model: NewTabPageCustomizationModel = NewTabPageCustomizationModel()) {
        self.model = model

        var onClose: (() -> Void)?
        super.init(rootView: NewTabPageCustomizationView(model: model, onClose: { onClose?() }))

        onClose = { [weak self] in
            self?.dismiss(animated: true)
        }

        model.onAllSettingsSelected = { [weak self] in
            guard let self else { return }
            dismiss(animated: true) {
                self.onAllSettingsSelected?()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }
}
