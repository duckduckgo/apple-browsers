//
//  OmniBarItemView.swift
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
import Combine

final class OmniBarItemView<Item: UIView>: UIView {
    let item: Item

    private var cancellables = Set<AnyCancellable>()

    init(_ item: Item) {
        self.item = item
        item.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        backgroundColor = .clear
        addSubview(item)

        setUpConstraints()

        self.translatesAutoresizingMaskIntoConstraints = false
        item.publisher(for: \.isHidden).sink { [weak self] isHidden in
            self?.isHidden = isHidden
        }.store(in: &cancellables)
    }

    deinit {
        cancellables.removeAll()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpConstraints() {
        NSLayoutConstraint.activate([
            item.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            item.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            item.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            item.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            item.centerXAnchor.constraint(equalTo: centerXAnchor),
            item.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
