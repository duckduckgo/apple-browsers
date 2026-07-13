//
//  TabsBarView.swift
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

final class TabsBarView: UIView {

    let collectionView: UICollectionView
    let buttonsStack = UIStackView()
    let buttonsBackground = UIView()

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(frame: frame)

        setUpSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isDirectionalLockEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false

        buttonsBackground.translatesAutoresizingMaskIntoConstraints = false

        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.axis = .horizontal
        buttonsStack.setContentHuggingPriority(.required, for: .horizontal)
        buttonsStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(collectionView)
        addSubview(buttonsBackground)
        addSubview(buttonsStack)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TabsBarViewController.Constants.leadingInset),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            buttonsBackground.leadingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            buttonsBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonsBackground.topAnchor.constraint(equalTo: topAnchor),
            buttonsBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            buttonsStack.leadingAnchor.constraint(equalTo: collectionView.trailingAnchor, constant: TabsBarViewController.Constants.leadingInset),
            buttonsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TabsBarViewController.Constants.leadingInset),
            buttonsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonsStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            buttonsStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
