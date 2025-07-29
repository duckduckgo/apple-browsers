//
//  FavoritesOverlay.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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
import Bookmarks
import Persistence

protocol FavoritesOverlayDelegate: AnyObject {
    
    func favoritesOverlay(_ overlay: FavoritesOverlay, didSelect favorite: BookmarkEntity)

}

class FavoritesOverlay: UIViewController {
    
    struct Constants {
        static let margin: CGFloat = 28
        static let ntpCompatibleMargin: CGFloat = 30
        static let footerPadding: CGFloat = 50
    }
    
    private let layout = UICollectionViewFlowLayout()
    var collectionView: UICollectionView!
    private var renderer: FavoritesHomeViewSectionRenderer!
    private let appSettings: AppSettings

    private lazy var borderView = StyledTopBottomBorderView()

    var isUsingSearchInputCustomStyling: Bool {
        get { renderer.isUsingSearchInputCustomStyling }
        set { renderer.isUsingSearchInputCustomStyling = newValue }
    }

    weak var delegate: FavoritesOverlayDelegate?


    init(viewModel: FavoritesListInteracting, appSettings: AppSettings = AppDependencyProvider.shared.appSettings) {
        renderer = FavoritesHomeViewSectionRenderer(allowsEditing: false,
                                                    viewModel: viewModel)
        self.appSettings = appSettings
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        
        collectionView.register(UINib(nibName: "FavoriteHomeCell", bundle: nil), forCellWithReuseIdentifier: "favorite")
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColor = .clear
        if isUsingSearchInputCustomStyling {
            collectionView.contentInsetAdjustmentBehavior = .always
        }

        view.addSubview(collectionView)

        if !isUsingSearchInputCustomStyling {
            borderView.insertSelf(into: view)
            borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
        }

        renderer.install(into: self)
        
        registerForKeyboardNotifications()
        
        decorate()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isPad {
            collectionView.flashScrollIndicators()
        }

    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if AppWidthObserver.shared.isLargeWidth {
            layout.minimumInteritemSpacing = 32
        } else {
            layout.minimumInteritemSpacing = 10
            if isUsingSearchInputCustomStyling {
                layout.minimumLineSpacing = 12
            }
        }
        
        collectionView.frame = view.bounds
    }
    
    private func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardDidShow),
                                               name: UIResponder.keyboardDidShowNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }
    
    @objc private func keyboardDidShow(notification: NSNotification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let keyboardFrameInView = self.view.convert(keyboardFrame, from: nil)
        let intersection = keyboardFrameInView.intersection(view.bounds)
        let offsetHeight = intersection.height - view.safeAreaInsets.bottom

        let inset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: offsetHeight, right: 0.0)
        collectionView.contentInset = inset
        collectionView.scrollIndicatorInsets = inset
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        collectionView.contentInset = .zero
        collectionView.scrollIndicatorInsets = .zero
    }
}

extension FavoritesOverlay: FavoritesHomeViewSectionRendererDelegate {
    
    func favoritesRenderer(_ renderer: FavoritesHomeViewSectionRenderer, didSelect favorite: BookmarkEntity) {
        delegate?.favoritesOverlay(self, didSelect: favorite)
    }
    
    func favoritesRenderer(_ renderer: FavoritesHomeViewSectionRenderer, didRequestEdit favorite: BookmarkEntity) {
        // currently can't edit favorites from overlay
    }

    func favoritesRenderer(_ renderer: FavoritesHomeViewSectionRenderer, favoriteDeleted favorite: BookmarkEntity) {
        // currently can't delete favorites from overlay
    }
    
}

extension FavoritesOverlay: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        renderer.collectionView(collectionView, didSelectItemAt: indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForFooterInSection section: Int) -> CGSize {
        return CGSize(width: 1, height: Constants.footerPadding)
    }
    
}

extension FavoritesOverlay: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return renderer.collectionView(collectionView, numberOfItemsInSection: section)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return renderer.collectionView(collectionView, cellForItemAt: indexPath)
    }
}

extension FavoritesOverlay: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath)
        -> CGSize {
            return renderer.collectionView(collectionView, layout: collectionViewLayout, sizeForItemAt: indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int)
        -> UIEdgeInsets {
            
            var insets = renderer.collectionView(collectionView, layout: collectionViewLayout, insetForSectionAt: section) ?? UIEdgeInsets.zero
            
            insets.top += isUsingSearchInputCustomStyling ? Constants.ntpCompatibleMargin : Constants.margin
            return insets
    }
}

extension FavoritesOverlay {
    
    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        view.backgroundColor = AppWidthObserver.shared.isLargeWidth ? .clear : theme.backgroundColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        view.backgroundColor = AppWidthObserver.shared.isLargeWidth ? .clear : ThemeManager.shared.currentTheme.backgroundColor
    }
}
