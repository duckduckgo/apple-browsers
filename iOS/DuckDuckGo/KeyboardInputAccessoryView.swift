//
//  KeyboardInputAccessoryView.swift
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

final class KeyboardInputAccessoryView: UIView {

    private let container = UIView()
    private var containerHeight: NSLayoutConstraint!
    var currentContent: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupContainer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
        setupContainer()
    }

    override var intrinsicContentSize: CGSize {
        let height = max(containerHeight.constant, 0)
        return CGSize(width: UIView.noIntrinsicMetric,
                height: height)
    }

    private func setupContainer() {
        addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false

        containerHeight = container.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerHeight
        ])
    }

    // MARK: - Public methods

    /// Swap in a new content view (fixed height), or nil to hide.
    func setContentView(_ view: UIView?, contentHeight: CGFloat = 48) {
        if let oldContent = currentContent {
            oldContent.removeFromSuperview()
        }

        guard let view else {
            currentContent = view
            containerHeight.constant = 0
            invalidateIntrinsicContentSize()
            return
        }

        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        containerHeight.constant = contentHeight
        currentContent = view

        invalidateIntrinsicContentSize()
        layoutIfNeeded()
    }
}
