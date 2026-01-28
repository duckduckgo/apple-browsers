//
//  BrowsingMenuSheetView.swift
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

import SwiftUI
import UIKit
import DesignResourcesKit
import DesignResourcesKitIcons
import Kingfisher

struct BrowsingMenuModel {
    var headerItems: [BrowsingMenuModel.Entry]
    var sections: [BrowsingMenuModel.Section]
}

struct BrowsingMenuSheetView: View {

    enum Metrics {
        static let headerButtonVerticalPadding: CGFloat = 12
        static let headerButtonHorizontalPadding: CGFloat = 8
        static let headerButtonIconSize: CGFloat = 26
        static let headerButtonIconTextSpacing: CGFloat = 4

        /// Approximate row size for `.insetGrouped` style.
        /// This is an estimate used for height calculation and may not exactly match
        /// the system-provided height in all configurations.
        static let defaultListRowHeight: CGFloat = 44

        /// Approximate spacing between list sections.
        /// Note: The actual UI uses `.compactSectionSpacingIfAvailable()` which applies
        /// `.compact` section spacing on iOS 17+. This value is an approximation and
        /// the actual spacing may differ slightly on earlier versions.
        static let listSectionSpacing: CGFloat = 20
        static let listTopPadding: CGFloat = 20
        static let grabberHeight: CGFloat = 20

        static let headerHorizontalSpacing: CGFloat = 10

        static let listTopPaddingAdjustment: CGFloat = 4

        static let websiteHeaderHeight: CGFloat = 56
        /// Height of header when only close button is shown (compact mode without website info)
        static let closeButtonHeaderHeight: CGFloat = 40
    }

    @Environment(\.dismiss) var dismiss
    @Environment(\.verticalSizeClass) var verticalSizeClass

    private let model: BrowsingMenuModel
    private let onDismiss: (_ wasActionSelected: Bool) -> Void

    @State private var highlightTag: BrowsingMenuModel.Entry.Tag?
    @State private var actionToPerform: (() -> Void)?
    @State private var isScrolledBelowHeader: Bool = false
    @State private var headerBottomY: CGFloat = 0

    private var isHeaderVisible: Bool {
        headerDataSource.isHeaderVisible || verticalSizeClass == .compact
    }

    @ObservedObject private(set) var headerDataSource: BrowsingMenuHeaderDataSource

    init(model: BrowsingMenuModel,
         headerDataSource: BrowsingMenuHeaderDataSource,
         highlightRowWithTag: BrowsingMenuModel.Entry.Tag? = nil,
         onDismiss: @escaping (_ wasActionSelected: Bool) -> Void) {
        self.model = model
        self.headerDataSource = headerDataSource
        self.onDismiss = onDismiss
        _highlightTag = State(initialValue: highlightRowWithTag)
    }

    var body: some View {
        List {
            headerSection
            menuSections
        }
        .compactSectionSpacingIfAvailable()
        .hideScrollContentBackground()
        .listStyle(.insetGrouped)
        .bounceBasedOnSizeIfAvailable()
        .padding(.top, -Metrics.listTopPaddingAdjustment)
        .background(.thickMaterial)
        .background(Color(designSystemColor: .background).opacity(0.1))
        .onDisappear(perform: {
            actionToPerform?()
            onDismiss(actionToPerform != nil)
        })
        .safeAreaInset(edge: .top, spacing: isHeaderVisible ? -Metrics.listTopPadding : 0, content: {
            if isHeaderVisible {
                websiteHeader
                    .background(headerPositionTracker)
                    .background {
                        if isScrolledBelowHeader && headerDataSource.isHeaderVisible {
                            Rectangle().fill(.thickMaterial)
                                .ignoresSafeArea()
                        }
                    }
                    .padding(.vertical, headerDataSource.isHeaderVisible ? 0 : -4)
            }
        })
        .tint(Color(designSystemColor: .textPrimary))
    }

    @ViewBuilder
    private var websiteHeader: some View {
        BrowsingMenuHeaderView(
            title: headerDataSource.title,
            displayURL: headerDataSource.displayURL,
            iconType: headerDataSource.iconType,
            isWebsiteInfoVisible: headerDataSource.isHeaderVisible,
            onDismiss: { dismiss() }
        )
        .padding(.horizontal, 20)
        .padding(.top, verticalSizeClass == .compact ? 8 : 16)
    }

    /// Tracks the header's bottom Y position in global coordinates
    private var headerPositionTracker: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    headerBottomY = geo.frame(in: .global).maxY
                }
                .onChangeUniversal(of: geo.frame(in: .global).maxY) { newValue in
                    headerBottomY = newValue
                }
        }
    }

    /// Invisible tracker that detects when content scrolls under the header
    private var scrollPositionTracker: some View {
        Color.clear
            .frame(height: 1)
            .background(
                GeometryReader { geo in
                    Color.clear.onChangeUniversal(of: geo.frame(in: .global).minY) { newValue in
                        isScrolledBelowHeader = newValue < headerBottomY
                    }
                }
            )
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            if !model.headerItems.isEmpty {
                HStack(spacing: Metrics.headerHorizontalSpacing) {
                    ForEach(model.headerItems) { headerItem in
                        MenuHeaderButton(entryData: headerItem) {
                            actionToPerform = { headerItem.action() }
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparatorTint(Color(designSystemColor: .lines))
        .listRowBackground(Color.clear)
        .overlay(alignment: .top) {
            if isHeaderVisible {
                scrollPositionTracker
            }
        }
    }

    @ViewBuilder
    private var menuSections: some View {
        ForEach(model.sections) { section in
            Section {
                ForEach(section.items) { item in
                    let isHighlighted = highlightTag != nil && item.tag == highlightTag

                    MenuRowButton(entryData: item, isHighlighted: isHighlighted) {
                        actionToPerform = { item.action() }
                        dismiss()
                    }
                    .listRowBackground(Color.rowBackgroundColor)
                }
            }
        }
        .listRowSeparatorTint(Color(designSystemColor: .lines))
    }
}

extension BrowsingMenuModel {
    struct Section: Identifiable {
        let id = UUID()
        let items: [BrowsingMenuModel.Entry]
    }

    struct Entry: Identifiable, Equatable {
        let id: UUID = UUID()
        let name: String
        let accessibilityLabel: String?
        let image: UIImage
        let showNotificationDot: Bool
        let customDotColor: UIColor?
        let detail: Detail?
        let action: () -> Void
        let tag: Tag?

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: BrowsingMenuModel.Entry, rhs: BrowsingMenuModel.Entry) -> Bool {
            lhs.id == rhs.id
        }

        enum Tag {
            case favorite
        }

        enum Detail {
            case text(String)
        }

        var hasDetails: Bool {
            showNotificationDot || detail != nil
        }
    }
}

extension BrowsingMenuModel.Entry {
    init?(_ browsingMenuEntry: BrowsingMenuEntry?, tag: Tag? = nil) {
        guard let browsingMenuEntry = browsingMenuEntry else { return nil }
        
        switch browsingMenuEntry {
        case .separator:
            assertionFailure(#function + " should not be called for .separator")

            return nil

        case .regular(let name, let accessibilityLabel, let image, let showNotificationDot, let customDotColor, let detail, let action):
            self.init(
                name: name,
                accessibilityLabel: accessibilityLabel,
                image: image,
                showNotificationDot: showNotificationDot,
                customDotColor: customDotColor,
                detail: detail.map { .text($0) },
                action: action,
                tag: tag
            )
        }
    }
}

private struct MenuRowButton: View {

    fileprivate let entryData: BrowsingMenuModel.Entry
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.iconTitleHorizontalSpacing) {
                Image(uiImage: entryData.image)
                    .padding(2)
                    .overlay {
                        if isHighlighted {
                            LottieView(lottieFile: "view_highlight", loopMode: .mode(.loop), isAnimating: .constant(true))
                                .scaledToFill()
                                .scaleEffect(1.3)
                        }
                    }

                HStack(spacing: Metrics.textDotHorizontalSpacing) {
                    Text(entryData.name)
                        .daxBodyRegular()

                    Spacer()

                    if entryData.hasDetails {
                        DetailView(entryData: entryData)
                    }
                }
            }
        }
        .accessibilityLabel(entryData.accessibilityLabel ?? entryData.name)
    }

    struct DetailView: View {
        fileprivate let entryData: BrowsingMenuModel.Entry

        var body: some View {
            HStack(spacing: Metrics.detailStackSpacing) {
                if entryData.showNotificationDot {
                    Circle().fill(entryData.customDotColor.map({ Color($0) }) ?? Color(designSystemColor: .accent))
                        .frame(width: Metrics.dotSize, height: Metrics.dotSize)
                }

                if let detail = entryData.detail {
                    switch detail {
                    case .text(let string):
                        Text(string)
                            .daxBodyRegular()
                            .foregroundStyle(Color(designSystemColor: .textSecondary))
                    }
                }
            }
        }
    }

    private struct Metrics {
        static let dotSize: CGFloat = 8.0
        static let detailStackSpacing: CGFloat = 4.0
        static let iconTitleHorizontalSpacing: CGFloat = 16
        static let textDotHorizontalSpacing: CGFloat = 4
    }
}

private struct MenuHeaderButton: View {

    private typealias Metrics = BrowsingMenuSheetView.Metrics

    fileprivate let entryData: BrowsingMenuModel.Entry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Metrics.headerButtonIconTextSpacing) {
                Image(uiImage: entryData.image)
                    .resizable()
                    .frame(width: Metrics.headerButtonIconSize, height: Metrics.headerButtonIconSize)
                    .tint(Color(designSystemColor: .icons))
                Text(entryData.name)
                    .daxCaption()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
            }
            .padding(.vertical, Metrics.headerButtonVerticalPadding)
            .padding(.horizontal, Metrics.headerButtonHorizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(Color.rowBackgroundColor)
            .menuHeaderEntryShape()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entryData.accessibilityLabel ?? entryData.name)
    }
}

private struct BrowsingMenuHeaderView: View {

    let title: String?
    let displayURL: String?
    let iconType: HeaderIconType
    let isWebsiteInfoVisible: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if isWebsiteInfoVisible {
                HStack(spacing: MenuHeaderConstant.contentSpacing) {
                    faviconView

                    textContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            closeButton
        }
        .padding(.vertical, MenuHeaderConstant.bottomPadding)
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
        }
        .buttonStyle(BrowsingMenuCloseButtonStyle())
        .accessibilityLabel(UserText.keyCommandClose)
    }

    @ViewBuilder
    private var faviconView: some View {
        Group {
            switch iconType {
            case .aiChat:
                Image(uiImage: DesignSystemImages.Color.Size24.aiChatGradient)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .easterEgg(let url):
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .favicon(let image):
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .globe:
                Image(uiImage: DesignSystemImages.Glyphs.Size24.globe)
                    .foregroundStyle(Color(designSystemColor: .icons))
            }
        }
        .frame(width: MenuHeaderConstant.faviconSize, height: MenuHeaderConstant.faviconSize)
        .menuHeaderEntryShape()
        .padding(MenuHeaderConstant.faviconPadding)
        .background(Color(designSystemColor: .controlsFillPrimary))
        .menuHeaderEntryShape()
    }

    @ViewBuilder
    private var textContent: some View {
        VStack(alignment: .leading, spacing: MenuHeaderConstant.textSpacing) {
            if let title, !title.isEmpty {
                Text(title)
                    .daxHeadline()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .lineLimit(1)
            }

            if let displayURL {
                Text(displayURL)
                    .daxCaption1()
                    .foregroundStyle(Color(designSystemColor: .textSecondary))
                    .lineLimit(1)
            }
        }
    }
}

private enum MenuHeaderConstant {
    static let cornerRadius: CGFloat = 10
    static let faviconSize: CGFloat = 32
    static let faviconPadding: CGFloat = 8
    static let contentSpacing: CGFloat = 12
    static let textSpacing: CGFloat = 2
    static let bottomPadding: CGFloat = 8
}

private extension View {
    @ViewBuilder
    func menuHeaderEntryShape() -> some View {
        if #available(iOS 17, *) {
            self
                .clipShape(ButtonBorderShape.automatic)
                .contentShape(ButtonBorderShape.automatic)
        } else {
            self
                .clipShape(RoundedRectangle(cornerRadius: MenuHeaderConstant.cornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: MenuHeaderConstant.cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func bounceBasedOnSizeIfAvailable() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    @ViewBuilder
    func onChangeUniversal<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}

private extension Color {
    static let rowBackgroundColor: Color = .init(designSystemColor: .surfaceTertiary)
}
