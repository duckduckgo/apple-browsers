//
//  FavoriteItemView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import DesignResourcesKitIcons
import SwiftUI
import UIComponents
import UIKit

struct FavoriteItemView: View {
    let favorite: Favorite
    let faviconLoading: FavoritesFaviconLoading?
    let isEditable: Bool
    let isolatesContextMenu: Bool
    let onMenuAction: ((MenuAction) -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            favoriteIcon

            Text(favorite.title)
                .font(Font.system(size: 12))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(favorite.title). \(UserText.favorite)")
    }

    @ViewBuilder
    private var favoriteIcon: some View {
        if isEditable && isolatesContextMenu {
            IsolatedFavoriteContextMenu(
                favorite: favorite,
                faviconLoading: faviconLoading,
                onMenuAction: onMenuAction
            )
            .frame(width: NewTabPageGrid.Item.edgeSize,
                   height: NewTabPageGrid.Item.edgeSize)
        } else {
            FavoriteIconView(favorite: favorite, faviconLoading: faviconLoading)
                .if(isEditable) {
                    $0.contextMenu {
                        contextMenuItems()
                    }
                }
        }
    }

    private func contextMenuItems() -> some View {
        Section(favorite.menuTitle) {
            Button {
                onMenuAction?(.edit)
            } label: {
                Label {
                    Text(UserText.favoriteMenuEdit)
                } icon: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.edit)
                }
            }

            Button {
                onMenuAction?(.delete)
            } label: {
                Label {
                    Text(UserText.favoriteMenuRemove)
                } icon: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.favoriteRemove)
                }
            }
        }
    }
}

private struct IsolatedFavoriteContextMenu: UIViewRepresentable {
    let favorite: Favorite
    let faviconLoading: FavoritesFaviconLoading?
    let onMenuAction: ((FavoriteItemView.MenuAction) -> Void)?

    func makeUIView(context: Context) -> FavoriteContextMenuView {
        FavoriteContextMenuView(
            favorite: favorite,
            faviconLoading: faviconLoading,
            onMenuAction: onMenuAction
        )
    }

    func updateUIView(_ view: FavoriteContextMenuView, context: Context) {
        view.update(
            favorite: favorite,
            faviconLoading: faviconLoading,
            onMenuAction: onMenuAction
        )
    }
}

private final class FavoriteContextMenuView: UIView, UIContextMenuInteractionDelegate {
    private let hostingController = UIHostingController(rootView: AnyView(EmptyView()))
    private var favorite: Favorite
    private var onMenuAction: ((FavoriteItemView.MenuAction) -> Void)?

    init(favorite: Favorite,
         faviconLoading: FavoritesFaviconLoading?,
         onMenuAction: ((FavoriteItemView.MenuAction) -> Void)?) {
        self.favorite = favorite
        self.onMenuAction = onMenuAction
        super.init(frame: .zero)

        backgroundColor = .clear
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        addInteraction(UIContextMenuInteraction(delegate: self))
        update(favorite: favorite, faviconLoading: faviconLoading, onMenuAction: onMenuAction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(favorite: Favorite,
                faviconLoading: FavoritesFaviconLoading?,
                onMenuAction: ((FavoriteItemView.MenuAction) -> Void)?) {
        self.favorite = favorite
        self.onMenuAction = onMenuAction
        hostingController.rootView = AnyView(
            FavoriteIconView(favorite: favorite, faviconLoading: faviconLoading)
                .id(favorite.id)
        )
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.makeMenu()
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        targetedPreview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        targetedPreview()
    }

    private func makeMenu() -> UIMenu {
        let edit = UIAction(title: UserText.favoriteMenuEdit,
                            image: DesignSystemImages.Glyphs.Size24.edit) { [weak self] _ in
            self?.onMenuAction?(.edit)
        }
        let remove = UIAction(title: UserText.favoriteMenuRemove,
                              image: DesignSystemImages.Glyphs.Size24.favoriteRemove) { [weak self] _ in
            self?.onMenuAction?(.delete)
        }
        return UIMenu(title: favorite.menuTitle, children: [edit, remove])
    }

    private func targetedPreview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: hostingController.view.bounds, cornerRadius: 12)
        return UITargetedPreview(view: hostingController.view, parameters: parameters)
    }
}

extension FavoriteItemView {
    enum MenuAction {
        case edit
        case delete
    }
}

#Preview {
    HStack(alignment: .top) {
        FavoriteItemView(favorite: Favorite(id: UUID().uuidString, title: "Text", domain: "facebook.com")).frame(width: 64)
        FavoriteItemView(favorite: Favorite(id: UUID().uuidString, title: "Lorem Ipsum is simply dummy text of the printing and typesetting industry", domain: "duckduckgo.com")).frame(width: 64)
    }
}

private extension FavoriteItemView {
    init(favorite: Favorite, isEditable: Bool = true) {
        self.init(favorite: favorite,
                  faviconLoading: nil,
                  isEditable: isEditable,
                  isolatesContextMenu: false,
                  onMenuAction: nil)
    }
}
