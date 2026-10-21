//
//  WhatsNewViewController.swift
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
import DesignResourcesKitIcons
import DesignResourcesKit
import RemoteMessaging

final class WhatsNewViewController: UINavigationController {
    private let displayModel: RemoteMessagingUI.CardsListDisplayModel
    private let onCloseButton: () -> Void

    init(displayModel: RemoteMessagingUI.CardsListDisplayModel, onCloseButton: @escaping () -> Void) {
        self.displayModel = displayModel
        self.onCloseButton = onCloseButton
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .portrait
        case .pad:
            return .all
        default:
            return .all
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        delegate = self
    }
}

// MARK: - Private

private extension WhatsNewViewController {

    func setupView() {
        let contentView = RemoteMessagingUI.CardsListView(displayModel: displayModel)
        let hostingController = UIHostingController(rootView: contentView)

        // Configure navigation bar
        let closeButton = UIBarButtonItem(
            image: DesignSystemImages.Glyphs.Size24.close,
            style: .plain,
            target: self,
            action: #selector(dismissModal)
        )
        closeButton.tintColor = UIColor(designSystemColor: .textPrimary)
        hostingController.navigationItem.rightBarButtonItem = closeButton

        setViewControllers([hostingController], animated: false)
    }

    @objc
    func dismissModal() {
        onCloseButton()
    }

    func resetNavigationBarColorToDefault() {
        let appearance = UINavigationBarAppearance()
        appearance.shadowColor = .clear
        appearance.backgroundColor = UIColor(singleUseColor: .whatsNewBackground)
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
    }

}

// MARK: - UINavigationControllerDelegate

extension WhatsNewViewController: UINavigationControllerDelegate {

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        // If we're presenting the root view controller we want to set the navigation bar to the same colour of the background.
        // In the other cases we set the background colour and tint colour of items to the default theme.
        if viewController is UIHostingController<RemoteMessagingUI.CardsListView> {
            resetNavigationBarColorToDefault()
        } else {
            decorateNavigationBar(navigationBar)
        }
    }
}
