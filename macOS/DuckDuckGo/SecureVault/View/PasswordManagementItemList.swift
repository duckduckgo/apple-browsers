//
//  PasswordManagementItemList.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Foundation
import SwiftUI
import BrowserServicesKit
import Combine
import SwiftUIExtensions
import DesignResourcesKitIcons

struct ScrollOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}

struct PasswordManagementItemListView: View {

    private enum Constants {
        static let dividerFadeInDistance: CGFloat = 100
    }

    @EnvironmentObject var model: PasswordManagementItemListModel
    @State var autoSelected = false
    @EnvironmentObject var themeManager: ThemeManager

    private var style: PasswordManagementStyle {
        PasswordManagementStyle.style(theme: themeManager.theme, isAppRebranded: themeManager.isAppRebranded)
    }

    private func selectItem(id: String, proxy: ScrollViewProxy) {
        // Selection/scroll wont work until list is fully rendered
        // so give it a few milis before auto-selecting
        if !autoSelected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                proxy.scrollTo(id, anchor: .center)
                autoSelected = true
            }
        }
    }

    var body: some View {

        VStack(spacing: 0) {
            PasswordManagementItemListCategoryView()
                .padding(.top, 15)
                .padding(.bottom, 14)
                .padding([.leading, .trailing], 10)
                .disabled(!model.canChangeCategory)
                .opacity(model.canChangeCategory ? 1.0 : 0.5)

            Divider()

            ScrollView {
                ScrollViewReader { proxy in
                    PasswordManagementItemListStackView(style: style)
                        .onChange(of: model.selected?.id) { itemId in
                            if let id = itemId {
                                selectItem(id: id, proxy: proxy)
                            }
                        }
                }
            }

            Spacer(minLength: 0)

            Divider()

            PasswordManagementAddButton(style: style)
                .environmentObject(themeManager)
                .padding(.vertical)
                .padding(.horizontal, 10)

        }
    }

}

struct PasswordManagementItemListCategoryView: View {

    @EnvironmentObject var model: PasswordManagementItemListModel

    var body: some View {

        HStack(alignment: .center) {

            NSPopUpButtonView<SecureVaultSorting.Category>(selection: $model.sortDescriptor.category, viewCreator: {
                let button = PopUpButton()

                for category in SecureVaultSorting.Category.allCases {
                    button.add(NSMenuItem(title: category.title, representedObject: category).withImage(category.image),
                               withForegroundColor: category.foregroundColor, backgroundColor: category.backgroundColor)

                    if category == .allItems {
                        button.menu?.addItem(NSMenuItem.separator())
                    }
                }

                button.sizeToFit()

                return button
            })
                .alignmentGuide(VerticalAlignment.center) { _ in
                    // Magic number to line up the pop up button with the sort button.
                    // The custom pop up button cell isn't getting the expected frame, making it look misaligned, so this is used
                    // to account for it.
                    return 11
                }

            // Separate branches for macOS 12 compatibility: SwiftUI can render the menu label as disabled when the image changes in place.
            if model.sortDescriptor.order == .ascending {
                PasswordManagementSortButton(imageName: "SortAscending")
            } else {
                PasswordManagementSortButton(imageName: "SortDescending")
            }
        }
        .padding(.vertical, -4)

    }
}

struct PasswordManagementItemListStackView: View {

    @EnvironmentObject var model: PasswordManagementItemListModel

    let style: PasswordManagementStyle

    var body: some View {
        LazyVStack(alignment: .leading) {
            PasswordManagementItemStackContentsView(style: style)
        }
    }

}

private struct ExternalPasswordManagerItemSection: View {
    @ObservedObject var model: PasswordManagementItemListModel

    let style: PasswordManagementStyle

    var body: some View {
        Section(header: Text(UserText.passwordManager).padding(.leading, 18).padding(.top, 0)) {
            PasswordManagerItemView(model: model, style: style) {
                model.externalPasswordManagerSelected = true
            }
            .padding(.horizontal, 10)
        }
    }
}

private struct SyncPromoItemSection: View {
    @ObservedObject var model: PasswordManagementItemListModel

    let style: PasswordManagementStyle

    var body: some View {
        Section {
            SyncPromoItemView(model: model, style: style) {
                model.syncPromoSelected = true
            }
            .padding(.horizontal, 10)
        }
    }
}

private struct PasswordManagementItemStackContentsView: View {

    @EnvironmentObject var model: PasswordManagementItemListModel

    let style: PasswordManagementStyle

    private var shouldDisplayExternalPasswordManagerRow: Bool {
        model.passwordManagerCoordinator.isEnabled &&
        (model.sortDescriptor.category == .allItems || model.sortDescriptor.category == .logins)
    }

    private var shouldDisplaySyncPromoRow: Bool {
        guard model.emptyState == .none && model.filter.isEmpty else {
            return false
        }

        switch model.sortDescriptor.category {
        case .allItems:
            return model.syncPromoManager.shouldPresentPromoFor(.autofill)
        case .logins:
            return model.syncPromoManager.shouldPresentPromoFor(.passwords)
        case .cards:
            return model.syncPromoManager.shouldPresentPromoFor(.creditCards)
        case .identities:
            return model.syncPromoManager.shouldPresentPromoFor(.identities)
        }
    }

    var body: some View {
        Spacer(minLength: 10)

        if shouldDisplayExternalPasswordManagerRow {
            ExternalPasswordManagerItemSection(model: model, style: style)
        } else if shouldDisplaySyncPromoRow {
            SyncPromoItemSection(model: model, style: style)
        }

        ForEach(Array(model.displayedSections.enumerated()), id: \.offset) { index, section in
            Section(header: Text(section.title).padding(.leading, 18).padding(.top, index == 0 ? 0 : 10)) {

                ForEach(section.items, id: \.id) { item in
                    ItemView(item: item, style: style) {
                        model.selected(item: item)
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        Spacer(minLength: 10)
    }

}

private struct PasswordManagerItemView: View {
    @ObservedObject var model: PasswordManagementItemListModel

    let style: PasswordManagementStyle
    let action: () -> Void

    private var isLocked: Bool {
        model.passwordManagerCoordinator.isLocked
    }

    private var lockStatusLabel: String {
        isLocked ? UserText.passwordManagerLockedStatus : UserText.passwordManagerUnlockedStatus
    }

    private var selected: Bool {
        model.externalPasswordManagerSelected
    }

    var body: some View {
        let textColor = style.textColor(selected: selected)
        let font = Font.system(size: 13)

        Button(action: action, label: {
            HStack(spacing: 3) {
                ZStack {
                    Image(.bitwardenIcon)

                    if isLocked {
                        Image(.passwordManagerLock)
                            .padding(.leading, 28)
                            .padding(.top, 21)
                    }

                }.frame(width: 32)
                    .padding(.leading, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.passwordManagerCoordinator.displayName)
                        .foregroundColor(textColor)
                        .font(font)
                    Text(lockStatusLabel)
                        .foregroundColor(textColor.opacity(0.8))
                        .font(font)
                }
                .padding(.leading, 4)
            }
        })
        .frame(maxHeight: 48)
        .buttonStyle(PasswordManagerItemButtonStyle(style: style, selected: selected))
    }
}

private struct SyncPromoItemView: View {
    @ObservedObject var model: PasswordManagementItemListModel

    let style: PasswordManagementStyle
    let action: () -> Void

    private var selected: Bool {
        model.syncPromoSelected
    }

    var body: some View {
        let textColor = style.textColor(selected: selected)
        let font = Font.system(size: 13)

        Button(action: action, label: {
            HStack(spacing: 2) {

                Image(.syncOK32)
                    .frame(width: 32)
                    .padding(.leading, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(UserText.syncPromoSidePanelTitle)
                        .foregroundColor(textColor)
                        .font(font)
                    Text(UserText.syncPromoSidePanelSubtitle)
                        .foregroundColor(textColor.opacity(0.8))
                        .font(font)
                }
                .padding(.leading, 4)
            }
        })
        .frame(maxHeight: 48)
        .buttonStyle(PasswordManagerItemButtonStyle(style: style, selected: selected))
    }
}

private struct ItemView: View {

    @EnvironmentObject var model: PasswordManagementItemListModel

    let item: SecureVaultItem
    let style: PasswordManagementStyle
    let action: () -> Void

    private var selected: Bool {
        model.selected == item
    }

    func getIconLetters(account: SecureVaultModels.WebsiteAccount) -> String {
        if let title = account.title, !title.isEmpty {
            return title
        }
        return model.tldForAccount(account)
    }

    var body: some View {
        let textColor = style.textColor(selected: selected)
        let font = Font.system(size: 13)

        Button(action: action, label: {
            HStack(spacing: 2) {

                switch item {
                case .account:
                    if let account = item.websiteAccount, let domain = account.domain {
                        LoginFaviconView(domain: domain, generatedIconLetters: getIconLetters(account: account))
                    } else {
                        LetterIconView(title: "#")
                    }
                case .card(let card):
                    Image(nsImage: card.iconImage)
                        .frame(width: 32)
                        .padding(.leading, 6)
                case .identity:
                    Image(.identity)
                        .frame(width: 32)
                        .padding(.leading, 6)
                case .note:
                    Image(.note)
                        .frame(width: 32)
                        .padding(.leading, 6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    switch item {
                    case .note:
                        Text(item.displayTitle)
                            .foregroundColor(textColor.opacity(0.7))
                            .font(font)
                        Text(item.displaySubtitle)
                            .foregroundColor(textColor.opacity(0.5))
                            .font(font)
                    default:
                        Text(item.displayTitle)
                            .foregroundColor(textColor)
                            .font(font)
                        Text(item.displaySubtitle)
                            .foregroundColor(textColor.opacity(0.8))
                            .font(font)
                    }
                }
                .padding(.leading, 4)
            }
        })
        .frame(maxHeight: 48)
        .buttonStyle(PasswordManagerItemButtonStyle(style: style, selected: selected))
    }

}

private struct PasswordManagerItemButtonStyle: ButtonStyle {

    let style: PasswordManagementStyle
    let selected: Bool

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .truncationMode(.tail)
            .background(RoundedRectangle(cornerRadius: style.backgroundCornerRadius, style: .continuous)
            .fill(style.backgroundColor(selected: selected)))
    }
}

private struct PasswordManagementSortButton: View {

    @EnvironmentObject var model: PasswordManagementItemListModel

    @State private var showHoverState = false

    let imageName: String

    private enum Constants {
        static let buttonSize: CGFloat = 24
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .foregroundColor(showHoverState ? .secureVaultCategoryDefault : .clear)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)

            Menu {
                Picker("", selection: $model.sortDescriptor.parameter) {
                    ForEach(SecureVaultSorting.SortParameter.allCases, id: \.self) { parameter in
                        Text(parameter.title)
                            .tag(parameter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)

                Divider()

                Picker("", selection: $model.sortDescriptor.order) {
                    ForEach(SecureVaultSorting.SortOrder.allCases, id: \.self) { order in
                        Text(order.title(for: model.sortDescriptor.parameter.type))
                            .tag(order)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            } label: {
                Image(imageName)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .contentShape(Rectangle())
            }
                .menuStyle(BorderlessButtonMenuStyle())
                .modifier(HideMenuIndicatorModifier())
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
        }
        .frame(width: Constants.buttonSize, height: Constants.buttonSize)
        .contentShape(Rectangle())
        .onHover { isOver in
            showHoverState = isOver
        }

    }

}

private struct PasswordManagementAddButton: View {

    @EnvironmentObject var model: PasswordManagementItemListModel
    let style: PasswordManagementStyle

    var body: some View {

        switch model.sortDescriptor.category {
        case .allItems:
            Text(UserText.pmAddItem)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: style.buttonCornerRadius)
                        .fill(Color(designSystemColor: .controlsFillPrimary))
                )
                .overlay {
                    Menu {
                        createMenuItem(image: Image(nsImage: DesignSystemImages.Glyphs.Size16.keyLogin),
                                       text: UserText.pmNewLogin,
                                       category: .logins)
                        createMenuItem(image: Image(nsImage: DesignSystemImages.Glyphs.Size16.profile),
                                       text: UserText.pmNewIdentity,
                                       category: .identities)
                        createMenuItem(image: Image(nsImage: DesignSystemImages.Glyphs.Size16.creditCard),
                                       text: UserText.pmNewCard,
                                       category: .cards)
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(RoundedRectangle(cornerRadius: style.buttonCornerRadius))
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                    .modifier(HideMenuIndicatorModifier())
                    .modifier(FlexibleButtonSizingModifier())
                }
                .padding(.vertical, -5)
        case .logins:
            createButton(text: UserText.pmAddLogin, category: model.sortDescriptor.category)
        case .identities:
            createButton(text: UserText.pmAddIdentity, category: model.sortDescriptor.category)
        case .cards:
            createButton(text: UserText.pmAddCard, category: model.sortDescriptor.category)
        }

    }

    private func createMenuItem(image: Image, text: String, category: SecureVaultSorting.Category) -> some View {
        Button {
            model.onAddItemClickedFor(category)
        } label: {
            HStack {
                image
                Text(text)
            }
        }
        .background(Color(designSystemColor: .controlsFillPrimary))
    }

    private func createButton(text: String, category: SecureVaultSorting.Category) -> some View {
        Button {
            model.onAddItemClickedFor(category)
        } label: {
            Text(text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: style.buttonCornerRadius)
                        .fill(Color(designSystemColor: .controlsFillPrimary))
                )
        }
        .buttonStyle(.plain)
        .padding(.vertical, -5)
    }
}

private struct HideMenuIndicatorModifier: ViewModifier {

    func body(content: Content) -> some View {
        content
            .menuIndicator(.hidden)
    }

}

private struct FlexibleButtonSizingModifier: ViewModifier {

    func body(content: Content) -> some View {
#if compiler(>=6.2) // Only compile in Xcode 26+ so that `buttonSizing` doesn't break compilation on older versions
        if #available(macOS 26, *) {
            content
                .buttonSizing(.flexible)
        } else {
            content
        }
#else
        content
#endif
    }

}

struct PasswordManagementStyle {
    let backgroundColor: Color
    let backgroundCornerRadius: CGFloat
    let buttonCornerRadius: CGFloat
    let textColor: Color
    let selectedBackgroundColor: Color
    let selectedTextColor: Color

    func backgroundColor(selected: Bool) -> Color {
        selected ? selectedBackgroundColor : backgroundColor
    }

    func textColor(selected: Bool) -> Color {
        selected ? selectedTextColor : textColor
    }

    static func style(theme: ThemeStyleProviding, isAppRebranded: Bool) -> PasswordManagementStyle {
        // Almost clear, so that whole view is clickable
        let clearBackgroundColor = Color(NSColor.windowBackgroundColor.withAlphaComponent(0.001))
        let controlTextColor = Color(NSColor.controlTextColor)

        guard isAppRebranded else {
            return PasswordManagementStyle(backgroundColor: clearBackgroundColor,
                                           backgroundCornerRadius: 3,
                                           buttonCornerRadius: 3,
                                           textColor: controlTextColor,
                                           selectedBackgroundColor: .accentColor,
                                           selectedTextColor: .white)
        }

        let selectedBackgroundColor = Color(theme.palette.controlsFillTertiary)
        return PasswordManagementStyle(backgroundColor: clearBackgroundColor,
                                       backgroundCornerRadius: 5,
                                       buttonCornerRadius: 5,
                                       textColor: controlTextColor,
                                       selectedBackgroundColor: selectedBackgroundColor,
                                       selectedTextColor: controlTextColor)
    }
}
