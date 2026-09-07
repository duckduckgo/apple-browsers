//
//  RedesignedNewTabPageViewController.swift
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

import DesignResourcesKit
import UIKit

/// A New Tab Page built as a vertical stack of independent blocks.
final class RedesignedNewTabPageViewController: UIViewController, NewTabPage {

    weak var delegate: NewTabPageControllerDelegate?
    weak var chromeDelegate: BrowserChromeDelegate?

    var isDragging: Bool { scrollView.isDragging }

    private let blocks: [any NewTabPageBlock]

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()

    private let blocksStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        return stackView
    }()

    init(blocks: [any NewTabPageBlock]) {
        self.blocks = blocks
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(designSystemColor: .alertYellow)
        addSubviews()
        installBlocks()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // The page is attached with alpha 0 ahead of a contextual dialog so content cannot flash
        // for a frame first, and is expected to restore it itself.
        view.alpha = 1
    }

    private func addSubviews() {
        view.addSubview(scrollView)
        scrollView.addSubview(blocksStackView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        blocksStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            blocksStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            blocksStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            blocksStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            blocksStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),

            // Pinning the content width to the visible width leaves block heights as the only
            // thing that can make the page scroll.
            blocksStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func installBlocks() {
        for block in blocks {
            let blockController = block.viewController

            addChild(blockController)
            blocksStackView.addArrangedSubview(blockController.view)
            blockController.didMove(toParent: self)
        }
    }

    func dismiss() {
        delegate = nil
        chromeDelegate = nil

        removeFromParent()
        view.removeFromSuperview()
    }

    /// No content on this page is sized from the page width.
    func widthChanged() {}
}

extension RedesignedNewTabPageViewController: HomeScreenTransitionSource {

    var snapshotView: UIView { view }

    var rootContainerView: UIView { view }
}

/// The logo and favorites blocks are not hosted on this page yet.
extension RedesignedNewTabPageViewController: NewTabPageContentHandoff {

    var isShowingLogo: Bool { false }

    var isShowingFavorites: Bool { false }

    var restingContentIsLogo: Bool { false }

    var restingContentIsFavorites: Bool { false }

    func setLogoHidden(_ hidden: Bool) {}

    func setFavoritesHidden(_ hidden: Bool) {}
}

extension RedesignedNewTabPageViewController: NewTabPageChromeAdapting {

    /// This page draws no framing border.
    func setChromeLayoutContext(isBorderSuppressed: Bool) {}
}

extension RedesignedNewTabPageViewController: NewTabPageEscapeHatchPresenting {

    /// The escape hatch will arrive as a block.
    func setEscapeHatch(_ model: EscapeHatchModel?) {}
}

/// Contextual dialogs are not hosted on this page yet.
extension RedesignedNewTabPageViewController: NewTabPageOnboardingPresenting {

    func showNextDaxDialog() {
        assertionFailure("Contextual onboarding is not implemented on the redesigned New Tab Page")
    }

    func onboardingCompleted() {
        assertionFailure("Contextual onboarding is not implemented on the redesigned New Tab Page")
    }

    func showDuckAIOnboardingCompletionWithActiveAddressBar(message: String, textEntryMode: TextEntryMode?) {
        assertionFailure("Contextual onboarding is not implemented on the redesigned New Tab Page")
    }

    func refreshContextualOnboardingDialogLayout() {}

    func dismissDuckAICompletionDialogIfNeededOnEditingEnd() {}
}
