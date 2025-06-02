//
//  BlankSnapshotViewController.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import Core
import Suggestions
import BrowserServicesKit

protocol BlankSnapshotViewRecoveringDelegate: AnyObject {
    
    func recoverFromPresenting(controller: BlankSnapshotViewController)
}

// Still some logic here that should be de-duplicated from MainViewController
class BlankSnapshotViewController: UIViewController {
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return ThemeManager.shared.currentTheme.statusBarStyle
    }

    private var tapInterceptView: UIView?

    let menuButton = MenuButton()

    var tabSwitcherButton: TabSwitcherButton!

    let addressBarPosition: AddressBarPosition
    let featureFlagger: FeatureFlagger
    let aiChatSettings: AIChatSettings
    let voiceSearchHelper: VoiceSearchHelperProtocol

    var viewCoordinator: MainViewCoordinator!

    weak var delegate: BlankSnapshotViewRecoveringDelegate?

    init(addressBarPosition: AddressBarPosition,
         aiChatSettings: AIChatSettings,
         voiceSearchHelper: VoiceSearchHelperProtocol,
         featureFlagger: FeatureFlagger) {
        self.addressBarPosition = addressBarPosition
        self.aiChatSettings = aiChatSettings
        self.voiceSearchHelper = voiceSearchHelper
        self.featureFlagger = featureFlagger
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tabSwitcherButton = ThemeManager.shared.properties.isExperimentalThemingEnabled ? TabSwitcherStaticButton() : TabSwitcherAnimatedButton()

        viewCoordinator = MainViewFactory.createViewHierarchy(self,
                                                              aiChatSettings: aiChatSettings,
                                                              voiceSearchHelper: voiceSearchHelper,
                                                              featureFlagger: featureFlagger)
        if addressBarPosition.isBottom {
            viewCoordinator.moveAddressBarToPosition(.bottom)
            viewCoordinator.hideToolbarSeparator()
        }

        configureOmniBar()

        if AppWidthObserver.shared.isLargeWidth {
            viewCoordinator.toolbar.isHidden = true
            viewCoordinator.constraints.navigationBarContainerTop.constant = 40
            configureTabBar()
        } else {
            viewCoordinator.toolbarTabSwitcherButton.customView = tabSwitcherButton
            viewCoordinator.menuToolbarButton.customView = menuButton
            menuButton.setState(.menuImage, animated: false)
            viewCoordinator.menuToolbarButton.customView = menuButton
        }

        addTapInterceptor()
        decorate()
    }


    private func addTapInterceptor() {
        let interceptView = UIView(frame: view.bounds)
        interceptView.backgroundColor = .clear
        interceptView.isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(userInteractionDetected))
        interceptView.addGestureRecognizer(tapGesture)

        view.addSubview(interceptView)
        tapInterceptView = interceptView
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        tapInterceptView?.removeFromSuperview()
        tapInterceptView = nil
    }

    // Need to do this at this phase to support split screen on iPad
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewCoordinator.toolbar.isHidden = AppWidthObserver.shared.isLargeWidth
    }

    private func configureTabBar() {
        let storyboard = UIStoryboard(name: "TabSwitcher", bundle: nil)
        guard let controller = storyboard.instantiateViewController(withIdentifier: "TabsBar") as? TabsBarViewController else {
            fatalError("Failed to instantiate tabs bar controller")
        }
        controller.view.frame = CGRect(x: 0, y: 24, width: view.frame.width, height: 40)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        
        controller.view.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 1.0).isActive = true
        controller.view.heightAnchor.constraint(equalToConstant: 40).isActive = true
        controller.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 24.0).isActive = true
        controller.view.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
    }
    
    private func configureOmniBar() {
        viewCoordinator.navigationBarCollectionView.register(OmniBarCell.self, forCellWithReuseIdentifier: "omnibar")
        viewCoordinator.navigationBarCollectionView.isPagingEnabled = true

        let layout = viewCoordinator.navigationBarCollectionView.collectionViewLayout as? UICollectionViewFlowLayout
        layout?.scrollDirection = .horizontal
        layout?.itemSize = CGSize(width: viewCoordinator.superview.frame.size.width, height: viewCoordinator.omniBar.barView.frame.height)
        layout?.minimumLineSpacing = 0
        layout?.minimumInteritemSpacing = 0
        layout?.scrollDirection = .horizontal

        viewCoordinator.navigationBarCollectionView.dataSource = self
        if AppWidthObserver.shared.isLargeWidth {
            viewCoordinator.omniBar.enterPadState()
        }
    }
    
    @IBAction func userInteractionDetected() {
        Pixel.fire(pixel: .blankOverlayNotDismissed)
        delegate?.recoverFromPresenting(controller: self)
    }
}

extension BlankSnapshotViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "omnibar", for: indexPath) as? OmniBarCell else {
            fatalError("Not \(OmniBarCell.self)")
        }
        cell.omniBar = viewCoordinator.omniBar
        return cell
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
}

extension BlankSnapshotViewController {
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        updateStatusBarBackgroundColor()
    }

    private func updateStatusBarBackgroundColor() {
        let theme = ThemeManager.shared.currentTheme

        if addressBarPosition == .bottom {
            viewCoordinator.statusBackground.backgroundColor = theme.backgroundColor
        } else {
            if AppWidthObserver.shared.isPad && traitCollection.horizontalSizeClass == .regular {
                viewCoordinator.statusBackground.backgroundColor = theme.tabsBarBackgroundColor
            } else {
                viewCoordinator.statusBackground.backgroundColor = theme.omniBarBackgroundColor
            }
        }
    }

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme

        setNeedsStatusBarAppearanceUpdate()

        view.backgroundColor = theme.mainViewBackgroundColor

        viewCoordinator.navigationBarContainer.backgroundColor = theme.barBackgroundColor
        viewCoordinator.navigationBarContainer.tintColor = theme.barTintColor

        viewCoordinator.toolbar.barTintColor = theme.barBackgroundColor
        viewCoordinator.toolbar.tintColor = theme.barTintColor

        viewCoordinator.toolbarTabSwitcherButton.tintColor = theme.barTintColor

        viewCoordinator.logoText.tintColor = theme.ddgTextTintColor
     }
    
}
