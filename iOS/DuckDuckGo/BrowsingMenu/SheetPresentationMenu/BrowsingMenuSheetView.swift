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

class BrowsingMenuSheetViewController: UIHostingController<BrowsingMenuSheetView> {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Required for material background to become effective
        view.backgroundColor = .clear
    }
}

struct BrowsingMenuModel {
    var headerItems: [BrowsingMenuModel.Entry]
    var sections: [BrowsingMenuModel.Section]
    var footerItems: [BrowsingMenuModel.Entry]
}

struct BrowsingMenuSheetView: View {

    enum Metrics {
        static let headerButtonVerticalPadding: CGFloat = 8
        static let headerButtonIconTextSpacing: CGFloat = 2
        static let footerButtonVerticalPadding: CGFloat = 8

        /// Approximate row size for `.insetGrouped` style.
        /// This is an estimate used for height calculation and may not exactly match
        /// the system-provided height in all configurations.
        static let defaultListRowHeight: CGFloat = 44

        /// Approximate spacing between list sections.
        /// Note: The actual UI uses `.compactSectionSpacingIfAvailable()` which applies
        /// `.compact` section spacing on iOS 17+. This value is an approximation and
        /// the actual spacing may differ slightly on earlier versions.
        static let listSectionSpacing: CGFloat = 20
        static let listTopPadding: CGFloat = 20 - listTopPaddingAdjustment
        static let grabberHeight: CGFloat = 20

        static let headerHorizontalSpacing: CGFloat = 10
        static let iconTitleHorizontalSpacing: CGFloat = 16
        static let textDotHorizontalSpacing: CGFloat = 4

        static let listTopPaddingAdjustment: CGFloat = 4
    }

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.verticalSizeClass) var verticalSizeClass

    private let model: BrowsingMenuModel
    private let onDismiss: (_ wasActionSelected: Bool) -> Void

    @State private var highlightTag: BrowsingMenuModel.Entry.Tag?
    @State private var actionToPerform: (() -> Void)?

    init(model: BrowsingMenuModel, highlightRowWithTag: BrowsingMenuModel.Entry.Tag? = nil, onDismiss: @escaping (_ wasActionSelected: Bool) -> Void) {
        self.model = model
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
        .floatingToolbar(
            footerItems: model.footerItems,
            actionToPerform: $actionToPerform,
            presentationMode: presentationMode,
            showsLabels: model.footerItems.count < 2
        )
        .safeAreaInset(edge: .top, content: {
            if verticalSizeClass == .compact {
                HStack {
                    Spacer()
                    Button(UserText.navigationTitleDone, role: .cancel) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 24)
                }
                .background(.thickMaterial)
                .padding(.bottom, -24)
            }
        })
        .tint(Color(designSystemColor: .textPrimary))
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            if !model.headerItems.isEmpty {
                HStack(spacing: Metrics.headerHorizontalSpacing) {
                    ForEach(model.headerItems) { headerItem in
                        MenuHeaderButton(entryData: headerItem) {
                            actionToPerform = { headerItem.action() }
                            presentationMode.wrappedValue.dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .background(.clear)
            }
        }
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparatorTint(Color(designSystemColor: .lines))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var menuSections: some View {
        ForEach(model.sections) { section in
            Section {
                ForEach(section.items) { item in
                    let isHighlighted = highlightTag != nil && item.tag == highlightTag

                    MenuRowButton(entryData: item, isHighlighted: isHighlighted) {
                        actionToPerform = { item.action() }
                        presentationMode.wrappedValue.dismiss()
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
    }
}

extension BrowsingMenuModel.Entry {
    init?(_ browsingMenuEntry: BrowsingMenuEntry?, tag: Tag? = nil) {
        guard let browsingMenuEntry = browsingMenuEntry else { return nil }
        
        switch browsingMenuEntry {
        case .separator:
            assertionFailure(#function + " should not be called for .separator")

            return nil

        case .regular(let name, let accessibilityLabel, let image, let showNotificationDot, let customDotColor, let action):
            self.init(
                name: name,
                accessibilityLabel: accessibilityLabel,
                image: image,
                showNotificationDot: showNotificationDot,
                customDotColor: customDotColor,
                action: action,
                tag: tag
            )
        }
    }
}

private typealias Metrics = BrowsingMenuSheetView.Metrics

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

                    if entryData.showNotificationDot {
                        Circle().fill(entryData.customDotColor.map({ Color($0) }) ?? Color(designSystemColor: .accent))
                            .frame(width: 8, height: 8)
                            .padding(.leading, 6)
                            .padding(.trailing, 12)

                        Spacer()
                    }
                }
            }
        }
        .accessibilityLabel(entryData.accessibilityLabel ?? entryData.name)
    }

}

private struct MenuHeaderButton: View {

    fileprivate let entryData: BrowsingMenuModel.Entry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Metrics.headerButtonIconTextSpacing) {
                Image(uiImage: entryData.image)
                    .tint(Color(designSystemColor: .icons))
                Text(entryData.name)
                    .daxFootnoteRegular()
                    .foregroundStyle(Color(designSystemColor: .textSecondary))
            }
            .padding(.vertical, Metrics.headerButtonVerticalPadding)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(Color.rowBackgroundColor)
            .menuHeaderEntryShape()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entryData.accessibilityLabel ?? entryData.name)
    }

    enum Constant {
        static let cornerRadius: CGFloat = 10
    }
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
                .clipShape(RoundedRectangle(cornerRadius: MenuHeaderButton.Constant.cornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: MenuHeaderButton.Constant.cornerRadius, style: .continuous))
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
}

private extension View {
    func floatingToolbar(
        footerItems: [BrowsingMenuModel.Entry],
        actionToPerform: Binding<(() -> Void)?>,
        presentationMode: Binding<PresentationMode>,
        showsLabels: Bool
    ) -> some View {
        modifier(FloatingToolbarModifier(
            footerItems: footerItems,
            actionToPerform: actionToPerform,
            presentationMode: presentationMode,
            showsLabels: showsLabels
        ))
    }
}

private struct FloatingToolbarModifier: ViewModifier {
    let footerItems: [BrowsingMenuModel.Entry]
    @Binding var actionToPerform: (() -> Void)?
    let presentationMode: Binding<PresentationMode>
    let showsLabels: Bool

    func body(content: Content) -> some View {
        if footerItems.isEmpty {
            content
        } else {
            content
                .overlay(alignment: .bottom, content: {
                    let colors = [
                        .clear,
                        Color(designSystemColor: .background).opacity(0.9),
                        Color(designSystemColor: .background)
                    ]
                    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                    // This makes the gradient extend to the full width and into the bottom safe area.
                        .ignoresSafeArea(edges: [.horizontal, .bottom])
                    // Together with previous modifier, this guarantees 8pt above the content of `safeAreaInset` below.
                        .frame(height: 8, alignment: .bottom)
                        .frame(maxWidth: .infinity)
                })
                .safeAreaInset(edge: .bottom, content: {
                    createBottomToolbar(labels: showsLabels)
                })
        }
    }

    @ViewBuilder
    private func createBottomToolbar(labels: Bool = false) -> some View {
        HStack(spacing: 4) {
            ForEach(footerItems) { footerItem in
                Button(action: {
                    actionToPerform = { footerItem.action() }
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(uiImage: footerItem.image)
                            .tint(Color(designSystemColor: .icons))
                        if labels {
                            Text(footerItem.name)
                                .daxBodyRegular()
                                .foregroundStyle(Color(designSystemColor: .textPrimary))
                        }
                    }
                    .padding(.vertical, Metrics.footerButtonVerticalPadding)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(footerItem.accessibilityLabel ?? footerItem.name)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 4, x: 0, y: 4)
        .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 2, x: 0, y: 1)
        .fixedSize(horizontal: true, vertical: true)
    }
}

private extension Color {
    static let rowBackgroundColor: Color = .init(designSystemColor: .surfaceTertiary)
}
