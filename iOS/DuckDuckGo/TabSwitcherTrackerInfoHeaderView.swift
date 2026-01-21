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
        static let horizontalPadding: CGFloat = 14
    }

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
        let rootView: AnyView = model.map { AnyView(InfoPanelView(model: $0)) } ?? AnyView(EmptyView())

        if let host {
            // If the host is parented to a different view controller, re-parent it
            if host.parent !== parent {
                host.willMove(toParent: nil)
                host.removeFromParent()
                parent.addChild(host)
                host.didMove(toParent: parent)
            }
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
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cleanupHostingController()
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

    private func cleanupHostingController() {
        guard let host else { return }
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        self.host = nil
    }

    deinit {
        // Note: cleanupHostingController() is called from prepareForReuse().
        // This deinit handles cases where reuse is skipped (e.g., collection
        // view teardown). UIKit guarantees deinit runs on main thread for
        // UIView subclasses.
        cleanupHostingController()
    }
}
