//
//  AutocompleteView.swift
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

import Foundation
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

struct AutocompleteView: View {

    @ObservedObject var model: AutocompleteViewModel

    var body: some View {
        List {
            if let sectionTitle = model.sectionTitle, !sectionTitle.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(sectionTitle)
                        .daxTitle3()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    Spacer(minLength: 0)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 2, bottom: 0, trailing: 0))
            }

            SuggestionsSection(suggestions: model.topHits,
                               query: model.query,
                               onSuggestionSelected: model.onSuggestionSelected,
                               onSuggestionDeleted: model.deleteSuggestion)

            SuggestionsSection(suggestions: model.ddgSuggestions,
                               query: model.query,
                               onSuggestionSelected: model.onSuggestionSelected,
                               onSuggestionDeleted: model.deleteSuggestion)

            SuggestionsSection(suggestions: model.localResults,
                               query: model.query,
                               onSuggestionSelected: model.onSuggestionSelected,
                               onSuggestionDeleted: model.deleteSuggestion)

            SuggestionsSection(suggestions: model.aiChatSuggestions,
                               query: model.query,
                               onSuggestionSelected: model.onSuggestionSelected,
                               onSuggestionDeleted: model.deleteSuggestion)

        }
        .offset(x: 0, y: -28)
        .padding(.bottom, -20)
        .padding(.top, model.isPad ? 10 : 0)
        .modifier(HideScrollContentBackground())
        .background(Color(designSystemColor: .background))
        .onHover { isHovering in
            if !isHovering {
                model.clearSelection()
            }
        }
        .modifier(CompactSectionSpacing())
        .modifier(DisableSelection())
        .modifier(DismissKeyboardOnSwipe())
        .environmentObject(model)
        .ignoresSafeArea(.keyboard, edges: .bottom)
   }

}

private struct DismissKeyboardOnSwipe: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.scrollDismissesKeyboard(.immediately)
        } else {
            content
        }
    }

}

private struct DisableSelection: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.selectionDisabled()
        } else {
            content
        }
    }

}

private struct CompactSectionSpacing: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.listSectionSpacing(.compact)
        } else {
            content
        }
    }

}

private struct HideScrollContentBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

private struct SuggestionSelectedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var suggestionIsSelected: Bool {
        get { self[SuggestionSelectedKey.self] }
        set { self[SuggestionSelectedKey.self] = newValue }
    }
}

private struct SuggestionsSection: View {

    @EnvironmentObject var autocompleteViewModel: AutocompleteViewModel

    let suggestions: [AutocompleteViewModel.SuggestionModel]
    let query: String?
    var onSuggestionSelected: (AutocompleteViewModel.SuggestionModel) -> Void
    var onSuggestionDeleted: (AutocompleteViewModel.SuggestionModel) -> Void

    let selectedColor = Color(designSystemColor: .accent)

    let unselectedColor = Color(designSystemColor: .surface)

    private struct Metrics {
        // Horizontal insets stay on the row to keep the separator's leading inset. Vertical insets
        // move inside the row content (below) so the hover/tap area covers the full row height.
        static let horizontalRowInsets = EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 14)
        static let verticalRowInsets = EdgeInsets(top: 10, leading: 0, bottom: 8, trailing: 0)
    }

    var body: some View {
        Section {
            ForEach(suggestions.indices, id: \.self) { index in
                 Button {
                     onSuggestionSelected(suggestions[index])
                 } label: {
                    SuggestionView(model: suggestions[index],
                                   query: query,
                                   onDelete: { onSuggestionDeleted(suggestions[index]) })
                        .padding(Metrics.verticalRowInsets)
                        .contentShape(Rectangle())
                 }
                 .listRowBackground(autocompleteViewModel.selection == suggestions[index] ? selectedColor : unselectedColor)
                 .listRowInsets(Metrics.horizontalRowInsets)
                 .listRowSeparatorTint(Color(designSystemColor: .lines), edges: [.bottom])
                 .onHover { isHovering in
                     if isHovering {
                         autocompleteViewModel.selection = suggestions[index]
                     }
                 }
            }
        }
    }

}

private struct SuggestionView: View {

    @EnvironmentObject var autocompleteModel: AutocompleteViewModel

    let model: AutocompleteViewModel.SuggestionModel
    let query: String?
    let onDelete: () -> Void

    var tapAheadImage: Image? {
        guard model.canShowTapAhead else { return nil }
        return Image(uiImage: autocompleteModel.isAddressBarAtBottom ?
                     DesignSystemImages.Glyphs.Size16.arrowCircleDownLeft : DesignSystemImages.Glyphs.Size16.arrowCircleUpLeft)
    }

    private var isSelected: Bool {
        autocompleteModel.selection == model
    }

    var body: some View {
        Group {

            switch model.suggestion {
            case .phrase(let phrase):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.findSearchSmall),
                                   title: phrase,
                                   query: query,
                                   indicator: tapAheadImage,
                                   onTapIndicator: { autocompleteModel.onTapAhead(model) })
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.SearchPhrase-\(phrase)")

            case .website(let url):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.globe),
                                   title: url.formattedForSuggestion())
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.Website-\(url.formattedForSuggestion())")

            case .bookmark(let title, let url, let isFavorite, _) where isFavorite:
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.bookmarkFavorite),
                                   title: title,
                                   subtitle: url.formattedForSuggestion())
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.Favorite-\(url.formattedForSuggestion())")

            case .bookmark(let title, let url, _, _):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.bookmark),
                                   title: title,
                                   subtitle: url.formattedForSuggestion())
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.Bookmark-\(url.formattedForSuggestion())")

            case .historyEntry(_, let url, _) where url.isDuckDuckGoSearch:
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.history),
                                   title: url.searchQuery ?? "",
                                   subtitle: UserText.autocompleteSearchDuckDuckGo,
                                   onDelete: onDelete)
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.SERPHistory-\(url.searchQuery ?? "")")

            case .historyEntry(let title, let url, _):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.history),
                                   title: title ?? "",
                                   subtitle: url.formattedForSuggestion(),
                                   onDelete: onDelete)
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.History-\(url.formattedForSuggestion())")

            case .openTab(title: let title, url: let url, _, _):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.tabsMobile),
                                   title: title,
                                   subtitle: "\(UserText.autocompleteSwitchToTab) · \(url.formattedForSuggestion())")
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.OpenTab-\(url.formattedForSuggestion())")

            case .internalPage, .unknown:
                FailedAssertionView("Unknown or unsupported suggestion type")

            case .askAIChat(value: let value):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.aiChat),
                                   title: value,
                                   subtitle: UserText.autocompleteAskAIChat)
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.AskAIChat-\(value)")

            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.suggestionIsSelected, isSelected)
    }

}

private struct SuggestionListItem: View {

    @EnvironmentObject var autocompleteModel: AutocompleteViewModel

    @Environment(\.suggestionIsSelected) private var isSelected: Bool

    let icon: Image
    let title: String
    let subtitle: String?
    let query: String?
    let indicator: Image?
    let onTapIndicator: (() -> Void)?
    let onDelete: (() -> Void)?

    init(icon: Image,
         title: String,
         subtitle: String? = nil,
         query: String? = nil,
         indicator: Image? = nil,
         onTapIndicator: ( () -> Void)? = nil,
         onDelete: (() -> Void)? = nil) {

        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.query = query
        self.indicator = indicator
        self.onTapIndicator = onTapIndicator
        self.onDelete = onDelete
    }

    // On a selected row the background is the accent fill, so content switches to the on-accent color to stay legible.
    private func contentColor(_ base: DesignSystemColor) -> Color {
        Color(designSystemColor: isSelected ? .accentContentPrimary : base)
    }

    var body: some View {
        HStack(spacing: 0) {
            icon
                .resizable()
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                .tintIfAvailable(contentColor(.icons))

            VStack(alignment: .leading, spacing: 0) {

                Group {
                    // Can't use dax modifiers because they are not typed for Text
                    if let query, title.hasPrefix(query) {
                        Text(query)
                            .font(Font(uiFont: UIFont.daxBodyRegular()))
                            .foregroundColor(contentColor(.textPrimary))
                        +
                        Text(title.dropping(prefix: query))
                            .font(Font(uiFont: UIFont.daxBodyBold()))
                            .foregroundColor(contentColor(.textPrimary))
                    } else {
                        Text(title)
                            .font(Font(uiFont: UIFont.daxBodyRegular()))
                                .foregroundColor(contentColor(.textPrimary))
                    }
                }
                .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .daxFootnoteRegular()
                        .foregroundColor(contentColor(.textSecondary))
                        .lineLimit(1)
                        .frame(minHeight: Metrics.subtitleMinHeight)
                }
            }
            .padding(.leading, Metrics.verticalSpacing)

            if indicator == nil && onDelete == nil {
                // No trailing accessory means we want to preserve the room for icon,
                // so all the titles from other cells are aligned.
                Spacer(minLength: Metrics.trailingPadding)
            } else {
                Spacer()
            }

            if let indicator {
                indicator
                    .highPriorityGesture(TapGesture().onEnded {
                        onTapIndicator?()
                    })
                    .tintIfAvailable(contentColor(.iconsSecondary))
                    .padding(.leading, Metrics.indicatorLeadingPadding)
            } else if let onDelete {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.clear)
                    .highPriorityGesture(TapGesture().onEnded {
                        onDelete()
                    })
                    .tintIfAvailable(contentColor(.iconsSecondary))
                    .padding(.leading, Metrics.indicatorLeadingPadding)
                    .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.DeleteButton")
                    .accessibilityLabel(UserText.actionDelete)
            }
        }
    }

    private struct Metrics {
        static let iconSize: CGFloat = 24
        static let verticalSpacing: CGFloat = 10
        static let trailingPadding: CGFloat = 20
        static let indicatorLeadingPadding: CGFloat = 4
        static let contentPadding: CGFloat = 3
        static let subtitleMinHeight: CGFloat = 21
    }

}
