//
//  TabSwitcherTrackerInfoHeaderView.swift
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

final class TabSwitcherTrackerInfoHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "TabSwitcherTrackerInfoHeaderView"
    static let estimatedHeight: CGFloat = 60

    private enum Constants {
        static let topPadding: CGFloat = 0
        static let horizontalPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 0
    }

    private weak var parentViewController: UIViewController?
    private var host: UIHostingController<AnyView>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    func configure(in parent: UIViewController, model: InfoPanelView.Model?) {
        parentViewController = parent
        let rootView: AnyView = model.map { AnyView(InfoPanelView(model: $0)) } ?? AnyView(EmptyView())

        if let host {
            host.rootView = rootView
            host.view.isHidden = (model == nil)
            setNeedsLayout()
            return
        }

        let host = UIHostingController(rootView: rootView)
        self.host = host

        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.isHidden = (model == nil)

        parent.addChild(host)
        addSubview(host.view)
        host.didMove(toParent: parent)

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: topAnchor, constant: Constants.topPadding),
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.bottomPadding)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        host?.rootView = AnyView(EmptyView())
        host?.view.isHidden = true
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)

        guard let host, !host.view.isHidden else {
            attributes.size.height = 0
            return attributes
        }

        let targetSize = CGSize(width: layoutAttributes.size.width, height: UIView.layoutFittingCompressedSize.height)
        let size = systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        attributes.size.height = size.height
        return attributes
    }

    deinit {
        host?.willMove(toParent: nil)
        host?.view.removeFromSuperview()
        host?.removeFromParent()
        host = nil
    }
}


