//
//  OmniBarProgressView.swift
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

final class OmniBarProgressView: UIView {
    let progressView = ProgressView()

    init() {
        super.init(frame: .zero)

        clipsToBounds = true
        backgroundColor = .clear
        isUserInteractionEnabled = false
        addSubview(progressView)

        progressView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            progressView.heightAnchor.constraint(equalToConstant: Metrics.progressBarHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    struct Metrics {
        static let progressBarHeight: CGFloat = 2
    }
}
