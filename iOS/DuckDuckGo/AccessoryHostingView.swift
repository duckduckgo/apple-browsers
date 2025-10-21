//
//  AccessoryHostingView.swift
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

final class AccessoryHostingView<AccessoryView: View>: UIView {

    private var hostingController: UIHostingController<AccessoryView>
    private let accessoryView: AccessoryView

    init(_ accessoryView: AccessoryView) {
        self.accessoryView = accessoryView
        self.hostingController = UIHostingController(rootView: accessoryView)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear

        guard let hosted = hostingController.view else { return }
        hosted.backgroundColor = .clear
        addSubview(hosted)
        frame.size = hosted.intrinsicContentSize
    }

    // MARK: - Sizing

    override var intrinsicContentSize: CGSize {
        hostingController.view.intrinsicContentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostingController.view.frame = bounds
    }
}
