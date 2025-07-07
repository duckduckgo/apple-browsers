//
//  TabBorderView.swift
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

final class TabBorderView: UIView {

    private let topEdge = UIView()
    private let bottomEdge = UIView()

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
        addSubview(topEdge)
        addSubview(bottomEdge)
    }

    private func setUpConstraints() {
        topEdge.translatesAutoresizingMaskIntoConstraints = false
        bottomEdge.translatesAutoresizingMaskIntoConstraints = false

        let height = Metrics.lineWidth

        NSLayoutConstraint.activate([
            topEdge.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topEdge.leadingAnchor.constraint(equalTo: leadingAnchor),
            topEdge.trailingAnchor.constraint(equalTo: trailingAnchor),
            topEdge.heightAnchor.constraint(equalToConstant: height),

            bottomEdge.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            bottomEdge.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomEdge.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomEdge.heightAnchor.constraint(equalToConstant: height)
        ])
    }

    private func setUpProperties() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        let edgeColor = UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(designSystemColor: .shadowTertiary)
            default:
                return UIColor(designSystemColor: .shadowSecondary)
            }
        }
        topEdge.backgroundColor = edgeColor
        bottomEdge.backgroundColor = edgeColor
    }

    private struct Metrics {
        static let lineWidth = 1.0
    }
}
