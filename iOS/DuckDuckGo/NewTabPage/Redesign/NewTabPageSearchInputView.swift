//
//  NewTabPageSearchInputView.swift
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

import AIChat
import DesignResourcesKit
import SwiftUI

/// Resting controls only. The browser's address bar owns every text editing session.
struct NewTabPageSearchInputView: View {

    let isModeToggleShown: Bool
    let isAIChatEnabled: Bool
    let isVoiceSearchEnabled: Bool
    let onActivate: (TextEntryMode) -> Void
    let onVoiceSearch: (TextEntryMode) -> Void

    @State private var textEntryMode: TextEntryMode

    init(isModeToggleShown: Bool,
         isAIChatEnabled: Bool,
         isVoiceSearchEnabled: Bool,
         initialTextEntryMode: TextEntryMode,
         onActivate: @escaping (TextEntryMode) -> Void,
         onVoiceSearch: @escaping (TextEntryMode) -> Void) {
        self.isModeToggleShown = isModeToggleShown
        self.isAIChatEnabled = isAIChatEnabled
        self.isVoiceSearchEnabled = isVoiceSearchEnabled
        self.onActivate = onActivate
        self.onVoiceSearch = onVoiceSearch
        _textEntryMode = State(initialValue: initialTextEntryMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isModeToggleShown {
                NewTabPageModeToggle(textEntryMode: $textEntryMode)
                    .frame(height: Metrics.toggleHeight)
                    .padding(.top, Metrics.cardPadding)
                    .padding(.horizontal, Metrics.cardPadding)
            }
            NewTabPageRestingSearchField(textEntryMode: textEntryMode,
                                        isAIChatButtonShown: isAIChatEnabled && !isModeToggleShown,
                                        isVoiceSearchEnabled: isVoiceSearchEnabled,
                                        onActivate: onActivate,
                                        onVoiceSearch: onVoiceSearch)
                .frame(height: Metrics.fieldHeight)
        }
        .background(cardBackground)
        .padding(.horizontal, Metrics.horizontalMargin)
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        return shape
            .fill(Color(designSystemColor: .surfaceSecondary))
            .overlay(shape.strokeBorder(Color(designSystemColor: .shadowPrimary), lineWidth: 1))
            .overlay(
                shape
                    .inset(by: 0.5)
                    .stroke(Color(designSystemColor: .highlightDecoration), lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            )
            .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 4, y: 2)
            .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 16, y: 8)
    }
}

private struct NewTabPageModeToggle: UIViewRepresentable {

    @Binding var textEntryMode: TextEntryMode

    func makeUIView(context: Context) -> UnifiedToggleInputToggleView {
        UnifiedToggleInputToggleView()
    }

    func updateUIView(_ view: UnifiedToggleInputToggleView, context: Context) {
        view.setMode(textEntryMode, animated: false)
        view.onModeChanged = { textEntryMode = $0 }
    }
}

private struct NewTabPageRestingSearchField: UIViewRepresentable {

    let textEntryMode: TextEntryMode
    let isAIChatButtonShown: Bool
    let isVoiceSearchEnabled: Bool
    let onActivate: (TextEntryMode) -> Void
    let onVoiceSearch: (TextEntryMode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(field: self)
    }

    func makeUIView(context: Context) -> DefaultOmniBarSearchView {
        let view = DefaultOmniBarSearchView(centersContentVertically: true)
        view.textField.isUserInteractionEnabled = false
        view.textField.isAccessibilityElement = false
        view.setLeftIconAreaHidden(true)
        view.privacyInfoContainer.isHidden = true
        view.notificationContainer.isHidden = true
        view.clearButton.isHidden = true
        view.reloadButton.isHidden = true
        view.cancelButton.isHidden = true
        view.customizableButton.isHidden = true
        view.separatorView.isHidden = true
        view.isModeToggleHidden = true

        // Give the non-editable placeholder a VoiceOver action without intercepting trailing buttons.
        let activateButton = context.coordinator.activateButton
        view.addSubview(activateButton)
        activateButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            activateButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            activateButton.trailingAnchor.constraint(equalTo: view.textField.trailingAnchor),
            activateButton.topAnchor.constraint(equalTo: view.topAnchor),
            activateButton.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        activateButton.addTarget(context.coordinator, action: #selector(Coordinator.activate), for: .touchUpInside)
        view.aiChatButton.addTarget(context.coordinator, action: #selector(Coordinator.activateAIChat), for: .touchUpInside)
        view.voiceSearchButton.addTarget(context.coordinator, action: #selector(Coordinator.activateVoiceSearch), for: .touchUpInside)
        view.aiChatButton.accessibilityLabel = UserText.duckAiFeatureName
        view.voiceSearchButton.accessibilityLabel = UserText.settingsVoiceSearch
        return view
    }

    func updateUIView(_ view: DefaultOmniBarSearchView, context: Context) {
        context.coordinator.field = self
        let placeholder = textEntryMode == .aiChat ? UserText.searchInputFieldPlaceholderDuckAI : UserText.searchDuckDuckGo
        view.textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(designSystemColor: .textSecondary)])
        context.coordinator.activateButton.accessibilityLabel = placeholder
        view.aiChatButton.isHidden = !isAIChatButtonShown
        view.voiceSearchButton.isHidden = !isVoiceSearchEnabled
    }

    final class Coordinator: NSObject {
        var field: NewTabPageRestingSearchField
        let activateButton = UIButton(type: .custom)

        init(field: NewTabPageRestingSearchField) {
            self.field = field
        }

        @objc func activate() {
            field.onActivate(field.textEntryMode)
        }

        @objc func activateAIChat() {
            field.onActivate(.aiChat)
        }

        @objc func activateVoiceSearch() {
            field.onVoiceSearch(field.textEntryMode)
        }
    }
}

private enum Metrics {
    static let horizontalMargin: CGFloat = 16
    static let cardPadding: CGFloat = 8
    static let cardCornerRadius: CGFloat = 28
    static let fieldHeight: CGFloat = 64
    static let toggleHeight: CGFloat = 40
}

#Preview("Toggle shown") {
    NewTabPageSearchInputView(isModeToggleShown: true,
                             isAIChatEnabled: true,
                             isVoiceSearchEnabled: true,
                             initialTextEntryMode: .search,
                             onActivate: { _ in },
                             onVoiceSearch: { _ in })
        .padding(.vertical, 40)
        .background(Color(designSystemColor: .background))
}

#Preview("Search only") {
    NewTabPageSearchInputView(isModeToggleShown: false,
                             isAIChatEnabled: false,
                             isVoiceSearchEnabled: false,
                             initialTextEntryMode: .search,
                             onActivate: { _ in },
                             onVoiceSearch: { _ in })
        .padding(.vertical, 40)
        .background(Color(designSystemColor: .background))
}
