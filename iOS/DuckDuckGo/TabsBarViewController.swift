//
//  TabsBarViewController.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import DesignResourcesKitIcons
import BrowserServicesKit

protocol TabsBarDelegate: NSObjectProtocol {
    
    func tabsBar(_ controller: TabsBarViewController, didSelectTabAtIndex index: Int)
    func tabsBar(_ controller: TabsBarViewController, didRemoveTabAtIndex index: Int)
    func tabsBar(_ controller: TabsBarViewController, didRequestMoveTabFromIndex fromIndex: Int, toIndex: Int)
    func tabsBarDidRequestNewTab(_ controller: TabsBarViewController)
    func tabsBarDidRequestForgetAll(_ controller: TabsBarViewController)
    func tabsBarDidRequestFireEducationDialog(_ controller: TabsBarViewController)
    func tabsBarDidRequestTabSwitcher(_ controller: TabsBarViewController)

}

class TabsBarViewController: UIViewController {

    public static let viewDidLayoutNotification = Notification.Name("com.duckduckgo.app.TabsBarViewControllerViewDidLayout")
    
    struct Constants {
        
        static let minItemWidth: CGFloat = 68
        static let buttonSize: CGFloat = 40
        static let stackSpacing: CGFloat = 12
    }
    
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var buttonsStack: UIStackView!
    @IBOutlet weak var buttonsBackground: UIView!

    lazy var fireButton: UIButton = {
        createButton(image: DesignSystemImages.Glyphs.Size24.fireSolid)
    }()

    lazy var addTabButton: UIButton = {
        createButton(image: DesignSystemImages.Glyphs.Size24.add)
    }()

    weak var delegate: TabsBarDelegate?
    private weak var tabsModel: TabsModel?

    private lazy var tabSwitcherButton: TabSwitcherButton = TabSwitcherStaticButton()

    private let longPressTabGesture = UILongPressGestureRecognizer()
    
    private weak var pressedCell: TabsBarCell?
    
    var tabsCount: Int {
        return tabsModel?.count ?? 0
    }
    
    var currentIndex: Int {
        return tabsModel?.currentIndex ?? 0
    }

    var maxItems: Int {
        return Int(collectionView.frame.size.width / Constants.minItemWidth)
    }

    static func createFromXib() -> TabsBarViewController {
        let storyboard = UIStoryboard(name: "TabSwitcher", bundle: nil)
        let controller: TabsBarViewController = storyboard.instantiateViewController(identifier: "TabsBar") { coder in
            TabsBarViewController(coder: coder)
        }
        return controller
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setUpSubviews()
        decorate()
        configureGestures()
        enableInteractionsWithPointer()
    }

    private func setUpSubviews() {

        collectionView.clipsToBounds = false
        collectionView.delegate = self
        collectionView.dataSource = self

        addTabButton.setImage(DesignSystemImages.Glyphs.Size24.add, for: .normal)
        fireButton.setImage(DesignSystemImages.Glyphs.Size24.fireSolid, for: .normal)

        buttonsStack.spacing = Constants.stackSpacing

        buttonsStack.addArrangedSubview(addTabButton)
        buttonsStack.addArrangedSubview(fireButton)
        buttonsStack.addArrangedSubview(tabSwitcherButton)

        addTabButton.addTarget(self, action: #selector(onNewTabPressed), for: .touchUpInside)
        fireButton.addTarget(self, action: #selector(onFireButtonPressed), for: .touchUpInside)
        tabSwitcherButton.delegate = self

        // Set width equal to height for all buttons
        [addTabButton, fireButton, tabSwitcherButton].forEach { button in
            button.widthAnchor.constraint(equalTo: button.heightAnchor).isActive = true
            button.widthAnchor.constraint(equalToConstant: Constants.buttonSize).isActive = true
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tabSwitcherButton.layoutSubviews()
        reloadData()
    }

    @IBAction func onFireButtonPressed() {
        
        func showClearDataAlert() {
            let alert = ForgetDataAlert.buildAlert(forgetTabsAndDataHandler: { [weak self] in
                guard let self = self else { return }
                self.delegate?.tabsBarDidRequestForgetAll(self)
            })
            self.present(controller: alert, fromView: fireButton)
        }

        delegate?.tabsBarDidRequestFireEducationDialog(self)
        showClearDataAlert()
    }

    @IBAction func onNewTabPressed() {
        requestNewTab()
    }

    func refresh(tabsModel: TabsModel?, scrollToSelected: Bool = false) {
        self.tabsModel = tabsModel
        
        tabSwitcherButton.isAccessibilityElement = true
        tabSwitcherButton.accessibilityLabel = UserText.tabSwitcherAccessibilityLabel
        tabSwitcherButton.accessibilityHint = UserText.numberOfTabs(tabsCount)

        let availableWidth = collectionView.frame.size.width
        let maxVisibleItems = min(maxItems, tabsCount)
        
        var itemWidth = availableWidth / CGFloat(maxVisibleItems)
        itemWidth = max(itemWidth, Constants.minItemWidth)
        itemWidth = min(itemWidth, availableWidth / 2)

        if let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.itemSize = CGSize(width: itemWidth, height: view.frame.size.height)
        }
        
        reloadData()

        if scrollToSelected {
            DispatchQueue.main.async {
                self.collectionView.scrollToItem(at: IndexPath(row: self.currentIndex, section: 0), at: .right, animated: true)
            }
        }

    }

    private func reloadData() {
        collectionView.reloadData()
        tabSwitcherButton.tabCount = tabsCount
    }

    func backgroundTabAdded() {
        reloadData()
        tabSwitcherButton.animateUpdate {
            self.tabSwitcherButton.tabCount = self.tabsCount
        }
    }
    
    private func configureGestures() {
        longPressTabGesture.addTarget(self, action: #selector(handleLongPressTabGesture))
        longPressTabGesture.minimumPressDuration = 0.2
        collectionView.addGestureRecognizer(longPressTabGesture)
    }
    
    @objc func handleLongPressTabGesture(gesture: UILongPressGestureRecognizer) {
        let locationInCollectionView = gesture.location(in: collectionView)
        
        switch gesture.state {
        case .began:
            guard let path = collectionView.indexPathForItem(at: locationInCollectionView) else { return }
            delegate?.tabsBar(self, didSelectTabAtIndex: path.row)

        case .changed:
            guard let path = collectionView.indexPathForItem(at: locationInCollectionView) else { return }
            if pressedCell == nil, let cell = collectionView.cellForItem(at: path) as? TabsBarCell {
                cell.isPressed = true
                pressedCell = cell
                collectionView.beginInteractiveMovementForItem(at: path)
            }
            let location = CGPoint(x: locationInCollectionView.x, y: collectionView.center.y)
            collectionView.updateInteractiveMovementTargetPosition(location)
            
        case .ended:
            collectionView.endInteractiveMovement()
            releasePressedCell()

        default:
            collectionView.cancelInteractiveMovement()
            releasePressedCell()
        }
    }

    private func releasePressedCell() {
        pressedCell?.isPressed = false
        pressedCell = nil
    }
    
    private func enableInteractionsWithPointer() {
        fireButton.isPointerInteractionEnabled = true
        addTabButton.isPointerInteractionEnabled = true
        tabSwitcherButton.pointer?.frame.size.width = 34
    }
    
    private func requestNewTab() {
        delegate?.tabsBarDidRequestNewTab(self)
        DispatchQueue.main.async {
            self.collectionView.scrollToItem(at: IndexPath(row: self.currentIndex, section: 0), at: .right, animated: true)
        }
    }

    private func createButton(image: UIImage) -> UIButton {
        let button = BrowserChromeButton()
        button.setImage(image)
        return button
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        NotificationCenter.default.post(name: TabsBarViewController.viewDidLayoutNotification, object: self)
    }
}

extension TabsBarViewController: TabSwitcherButtonDelegate {
    
    func showTabSwitcher(_ button: TabSwitcherButton) {
        delegate?.tabsBarDidRequestTabSwitcher(self)
    }
    
    func launchNewTab(_ button: TabSwitcherButton) {
        requestNewTab()
    }
        
}

extension TabsBarViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.tabsBar(self, didSelectTabAtIndex: indexPath.row)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return true
    }

    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return true
    }

    func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        return proposedIndexPath
    }

    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        delegate?.tabsBar(self, didRequestMoveTabFromIndex: sourceIndexPath.row, toIndex: destinationIndexPath.row)
    }
    
}

extension TabsBarViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabsCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Tab", for: indexPath) as? TabsBarCell else {
            fatalError("Unable to create TabBarCell")
        }
        
        guard let model = tabsModel?.get(tabAt: indexPath.row) else {
            fatalError("Failed to load tab at \(indexPath.row)")
        }
        let isCurrent = indexPath.row == currentIndex
        let isNextCurrent = indexPath.row + 1 == currentIndex
        cell.update(model: model, isCurrent: isCurrent, isNextCurrent: isNextCurrent, withTheme: ThemeManager.shared.currentTheme)
        cell.onRemove = { [weak self, weak model] in
            guard let self = self, let model = model,
                let tabIndex = self.tabsModel?.indexOf(tab: model)
                else { return }
            self.delegate?.tabsBar(self, didRemoveTabAtIndex: tabIndex)
        }
        return cell
    }

}

extension TabsBarViewController {

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        view.backgroundColor = theme.tabsBarBackgroundColor
        view.tintColor = theme.barTintColor
        collectionView.backgroundColor = theme.tabsBarBackgroundColor
        buttonsBackground.backgroundColor = theme.tabsBarBackgroundColor
        
        collectionView.reloadData()
    }

}

extension MainViewController: TabsBarDelegate {
  
    func tabsBar(_ controller: TabsBarViewController, didSelectTabAtIndex index: Int) {
        dismissOmniBar()
        select(tabAt: index)
    }
    
    func tabsBar(_ controller: TabsBarViewController, didRemoveTabAtIndex index: Int) {
        let tab = tabManager.model.get(tabAt: index)
        closeTab(tab)
    }
    
    func tabsBar(_ controller: TabsBarViewController, didRequestMoveTabFromIndex fromIndex: Int, toIndex: Int) {
        tabManager.model.moveTab(from: fromIndex, to: toIndex)
        select(tabAt: toIndex)
    }
    
    func tabsBarDidRequestNewTab(_ controller: TabsBarViewController) {
        newTab()
    }
    
    func tabsBarDidRequestForgetAll(_ controller: TabsBarViewController) {
        forgetAllWithAnimation()
    }
    
    func tabsBarDidRequestFireEducationDialog(_ controller: TabsBarViewController) {
        currentTab?.dismissContextualDaxFireDialog()
        ViewHighlighter.hideAll()
    }
    
    func tabsBarDidRequestTabSwitcher(_ controller: TabsBarViewController) {
        showTabSwitcher()
    }
    
}
