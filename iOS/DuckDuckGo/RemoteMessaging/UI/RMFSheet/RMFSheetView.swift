//
//  RMFSheetView.swift
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI

/// The RMF sheet template. The sheet's height comes from its presentation; see `RMFSheetPresenter`.
struct RMFSheetView: View {

    enum Layout {
        case phone
        /// A form sheet over a regular-width iPad window. Its own size class is always compact, so the presenter decides.
        case formSheet
    }

    let content: RMFSheetContent
    var layout: Layout
    let onAction: (RMFSheetAction) -> Void

    @State private var selectedChoiceID: String?

    init(content: RMFSheetContent, layout: Layout = .phone, onAction: @escaping (RMFSheetAction) -> Void) {
        self.content = content
        self.layout = layout
        self.onAction = onAction
        _selectedChoiceID = State(initialValue: content.choiceList?.preselectedID)
    }

    private var metrics: Metrics {
        layout == .formSheet ? .iPad : .phone
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if #available(iOS 16, *) {
                // Scrolls only when the content doesn't fit the sheet.
                ViewThatFits(in: .vertical) {
                    layout(scrolls: false)
                    layout(scrolls: true)
                }
            } else {
                layout(scrolls: true)
            }
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rmfSheet")
    }

    @ViewBuilder
    private func layout(scrolls: Bool) -> some View {
        VStack(spacing: 0) {
            if scrolls {
                ScrollView { main }
            } else {
                main
                Spacer(minLength: 0)
            }
            footer
        }
    }

    // MARK: - Parts

    private var topBar: some View {
        HStack {
            Spacer()
            if content.exit.showsCloseButton {
                CloseButton { onAction(.close) }
            }
        }
        .padding(.top, metrics.topBarTopPadding)
        .padding(.horizontal, Metrics.topBarInlinePadding)
        .frame(minHeight: content.height == .full ? Metrics.topBarHeight : nil, alignment: .top)
    }

    private var main: some View {
        VStack(spacing: 0) {
            if let media = content.media {
                media
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.mediaSize, height: Metrics.mediaSize)
                    .padding(.bottom, Metrics.mediaTrailing)
                    .accessibilityHidden(true)
            }

            VStack(spacing: Metrics.textGap) {
                if let label = content.label, label.style == .new {
                    LabelView(label: label)
                }
                Text(content.title)
                    .daxTitle1()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .accessibilityAddTraits(.isHeader)
                if let label = content.label, label.style == .subtle {
                    LabelView(label: label)
                        .padding(.bottom, Metrics.subtleLabelBottomPadding)
                }
                if let body = content.body {
                    Text(body)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Metrics.contentLeading)

            if let choiceList = content.choiceList {
                ChoiceListView(choiceList: choiceList, selectedID: $selectedChoiceID)
                    .padding(.top, Metrics.contentBlockGap)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, content.height == .full ? Metrics.fullHeightTopPadding : 0)
        .padding(.horizontal, metrics.inlinePadding)
    }

    private var footer: some View {
        VStack(spacing: Metrics.actionGap) {
            Button(content.primaryButtonTitle) {
                onAction(.primary(selectedChoiceID: selectedChoiceID))
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("rmfSheetPrimaryButton")

            if let secondaryTitle = content.exit.secondaryButtonTitle {
                Button(secondaryTitle) { onAction(.secondary) }
                    .buttonStyle(SecondaryFillButtonStyle())
                    .accessibilityIdentifier("rmfSheetSecondaryButton")
            }

            if let footnote = content.footnote {
                Text(footnote)
                    .daxSubheadRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, metrics.contentToActions)
        .padding(.bottom, metrics.bottomPadding)
        .padding(.horizontal, metrics.inlinePadding)
    }
}

// MARK: - Components

private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if #available(iOS 26, *) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .icons))
                    .padding(RMFSheetView.Metrics.closeButtonPadding)
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    .renderingMode(.template)
            }
        }
        .modifier(CloseButtonStyleBeforeGlass())
        .accessibilityLabel(UserText.keyCommandClose)
        .accessibilityIdentifier("rmfSheetCloseButton")
    }
}

/// Glass buttons draw their own background; earlier systems use the standard grey circle.
private struct CloseButtonStyleBeforeGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.plain)
        } else {
            content.buttonStyle(CloseButtonStyle())
        }
    }
}

private struct LabelView: View {
    let label: RMFSheetContent.Label

    var body: some View {
        switch label.style {
        case .new:
            Text(label.text)
                .daxFootnoteSemibold()
                .foregroundColor(.black)
                .padding(.vertical, 3)
                .padding(.horizontal, 10)
                .background(Capsule().fill(Color(designSystemColor: .alertYellow)))
        case .subtle:
            Text(label.text)
                .daxFootnoteSemibold()
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
    }
}

private struct ChoiceListView: View {
    let choiceList: RMFSheetContent.ChoiceList
    @Binding var selectedID: String?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(choiceList.choices) { choice in
                ChoiceRow(choice: choice, isSelected: choice.id == selectedID) {
                    selectedID = choice.id
                }
            }
        }
    }
}

private struct ChoiceRow: View {
    let choice: RMFSheetContent.ChoiceList.Choice
    let isSelected: Bool
    let select: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    if let description = choice.description {
                        Text(description)
                            .daxSubheadRegular()
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                RadioIndicator(isOn: isSelected)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(shape.fill(isSelected ? Color(designSystemColor: .accentGlowSecondary) : .clear))
            .overlay(
                shape.strokeBorder(Color(designSystemColor: isSelected ? .accentPrimary : .lines),
                                   lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("rmfSheetChoice.\(choice.id)")
    }
}

private struct RadioIndicator: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Color(designSystemColor: .accentPrimary))
                Circle().fill(Color.white).frame(width: 10, height: 10)
            } else {
                Circle().strokeBorder(Color(designSystemColor: .decorationTertiary), lineWidth: 2)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

// MARK: - Metrics

extension RMFSheetView {
    /// Values from the RMF Spacing variables in the RMF Sheet Figma spec.
    struct Metrics {
        let topBarTopPadding: CGFloat
        let inlinePadding: CGFloat
        let contentToActions: CGFloat
        let bottomPadding: CGFloat

        static let phone = Metrics(topBarTopPadding: 20, inlinePadding: 24, contentToActions: 20, bottomPadding: 24)
        static let iPad = Metrics(topBarTopPadding: 16, inlinePadding: 64, contentToActions: 40, bottomPadding: 64)

        static let topBarInlinePadding: CGFloat = 20
        static let topBarHeight: CGFloat = 64
        static let closeButtonPadding: CGFloat = 10
        /// Card outer margin plus card top padding.
        static let fullHeightTopPadding: CGFloat = 40
        static let mediaSize: CGFloat = 96
        static let mediaTrailing: CGFloat = 8
        static let contentLeading: CGFloat = 16
        static let textGap: CGFloat = 8
        static let subtleLabelBottomPadding: CGFloat = 12
        static let contentBlockGap: CGFloat = 20
        static let actionGap: CGFloat = 8
    }
}

// MARK: - Previews

#Preview("Content height") {
    RMFSheetView(content: .init(
        media: Image(uiImage: DesignSystemImages.Color.Size96.cookieCheckFeature),
        label: .init(text: "New", style: .new),
        title: "Title goes here",
        body: "Body text explains the benefit in one or two short sentences.",
        choiceList: .init(choices: [
            .init(id: "accept", title: "Accept cookies that can't be rejected", description: "Saves you a click on most sites"),
            .init(id: "keep", title: "I'll keep accepting them myself", description: "Nothing changes")
        ], preselectedID: "accept"),
        primaryButtonTitle: "Primary action",
        exit: .closeAndSecondaryButton("Not now"),
        footnote: "You can change this any time in Settings."
    ), onAction: { _ in })
}
