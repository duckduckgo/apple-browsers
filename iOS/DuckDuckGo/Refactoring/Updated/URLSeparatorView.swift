//
//  URLSeparatorView.swift
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
import DesignResourcesKit

final class URLSeparatorView: UIView {

    private let lineView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        setUpSubviews()
        setUpConstraints()
        setUpProperties()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        addSubview(lineView)
    }

    private func setUpConstraints() {
        NSLayoutConstraint.activate([
            lineView.widthAnchor.constraint(equalToConstant: Metrics.width),
            lineView.heightAnchor.constraint(equalToConstant: Metrics.height),

            lineView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            lineView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            lineView.centerYAnchor.constraint(equalTo: centerYAnchor),
            lineView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            lineView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func setUpProperties() {
        lineView.backgroundColor = UIColor(designSystemColor: .lines)
        lineView.translatesAutoresizingMaskIntoConstraints = false
    }

    private struct Metrics {
        static let width: CGFloat = 1.0
        static let height: CGFloat = 20.0
    }
}
