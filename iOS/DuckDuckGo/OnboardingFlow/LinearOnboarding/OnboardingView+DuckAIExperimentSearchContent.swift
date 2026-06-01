//
//  OnboardingView+DuckAIExperimentSearchContent.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import Onboarding
import QuartzCore
import SwiftUI
import UIComponents
import UIKit

extension OnboardingView {
    private enum Metrics {
        // MARK: Spacing
        static let contentVerticalSpacing: CGFloat = 16
        static let legacyTitleToPickerTopPadding: CGFloat = 8
        static let rebrandedTitleToPickerTopPadding: CGFloat = 16
        static let fieldToFirstChipTopPadding: CGFloat = 16
        static let queryFieldBottomPadding: CGFloat = -8
        static let queryFieldTopPadding: CGFloat = -12
        static let queryFieldContentSpacing: CGFloat = 8
        static let queryFieldHorizontalPadding: CGFloat = 16
        static let queryFieldVerticalPadding: CGFloat = 16.33
        static let disabledPrimaryActionOpacity: CGFloat = 0.3

        // MARK: Sizing
        static let pickerWidth: CGFloat = 216
        static let pickerHeight: CGFloat = 38
        static let pickerContainerHeight: CGFloat = 40
        static let pickerVerticalPadding: CGFloat = 0.5
        static let pickerBottomPadding: CGFloat = 4
        static let singleLineFieldHeight: CGFloat = 26
        static let multilineFieldHeight: CGFloat = 56
        static let queryFieldActionButtonSize: CGFloat = 28
        static let queryFieldCornerRadius: CGFloat = 14
        static let queryFieldInnerBorderInset: CGFloat = 2
        static let maxSuggestionCount = 3
        static let legacyQueryFieldBorderWidth: CGFloat = 1
        static let rebrandedQueryFieldBorderWidth: CGFloat = 1

        // MARK: Animation
        static let controlsRevealDelayAfterTitleAnimation: TimeInterval = 0.3
        static let keyboardFocusDelayAfterControlsReveal: TimeInterval = 0.2
        static let legacyInitialInputFocusDelayAfterAppear: TimeInterval = 0.35
        static let rebrandedInitialInputFocusDelayAfterAppear: TimeInterval = 0.55
        static let suggestionInitialRevealDelay: TimeInterval = 0.8
        static let pickerSelectionAnimationDuration: TimeInterval = 0.22
        static let contentFadeAnimationDuration: TimeInterval = 0.2
        static let suggestionSpringMass: CGFloat = 0.7
        static let suggestionSpringStiffness: CGFloat = 180
        static let suggestionSpringDamping: CGFloat = 14
        static let suggestionSpringInitialVelocity: CGFloat = 0.25

        // MARK: Offset
        static let queryFieldActionOffsetX: CGFloat = 2.33
        static let queryFieldActionOffsetY: CGFloat = 1
    }

    struct DuckAIExperimentSearchContent: View {
        // MARK: Types
        enum VisualStyle {
            case legacy
            case rebranded
        }

        // MARK: Dependencies
        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let content: OnboardingDuckAIQueryContent
        private let onModeConfirmed: (DuckAIQueryMode) -> Void
        private let openAIChatAction: (String?, Bool) -> Void
        private let openSearchAction: (String) -> Void
        private let measureQuerySubmissionAction: (DuckAIQueryMode, DuckAIQueryPromptSource) -> Void
        private let startExitTransitionAction: () -> Void
        private let visualStyle: VisualStyle
        private var animateTitle: Binding<Bool>
        @StateObject private var pickerViewModel: ImageSegmentedPickerViewModel
        private let suggestionsViewModel = OnboardingDuckAIExperimentSuggestionsViewModel()

        // MARK: State
        @State private var query = ""
        @State private var selectedMode: DuckAIQueryMode
        @State private var isInputFocused = false
        @State private var visibleSuggestionCount = 0
        @State private var isTransitioningOut = false
        @State private var suggestionSequenceStarted = false
        @State private var showInteractiveControls = false
        @State private var hasStartedEntranceSequence = false
        @State private var hasPassedInitialFocusDelay = false
        @State private var shouldFocusWhenInitialDelayPasses = false
        /// Local typing-start trigger for the rebranded `TypingText` (the rebranded call site
        /// doesn't pass an `animateTitle` binding).
        @State private var rebrandedAnimateTitle = false

        // MARK: Constants
        private static let pickerItems: [ImageSegmentedPickerItem] = [
            ImageSegmentedPickerItem(
                text: UserText.searchInputToggleSearchButtonTitle,
                selectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.findSearchGradientColor),
                unselectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.findSearch)
            ),
            ImageSegmentedPickerItem(
                text: UserText.Onboarding.DuckAIQueryExperiment.toggleAILabel,
                selectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.aiChatGradientColor),
                unselectedImage: Image(uiImage: DesignSystemImages.Glyphs.Size16.aiChat)
            )
        ]

        init(
            content: OnboardingDuckAIQueryContent = .init(
                title: UserText.Onboarding.DuckAIQueryExperiment.title,
                searchPlaceholder: UserText.Onboarding.DuckAIQueryExperiment.searchPlaceholder,
                aiPlaceholder: UserText.Onboarding.DuckAIQueryExperiment.aiPlaceholder,
                isToggleVisible: true
            ),
            defaultMode: DuckAIQueryMode,
            visualStyle: VisualStyle = .legacy,
            animateTitle: Binding<Bool> = .constant(false),
            onModeConfirmed: @escaping (DuckAIQueryMode) -> Void,
            openAIChatAction: @escaping (String?, Bool) -> Void,
            openSearchAction: @escaping (String) -> Void,
            measureQuerySubmissionAction: @escaping (DuckAIQueryMode, DuckAIQueryPromptSource) -> Void,
            startExitTransitionAction: @escaping () -> Void
        ) {
            self.content = content
            self.onModeConfirmed = onModeConfirmed
            self.openAIChatAction = openAIChatAction
            self.openSearchAction = openSearchAction
            self.measureQuerySubmissionAction = measureQuerySubmissionAction
            self.startExitTransitionAction = startExitTransitionAction
            self.visualStyle = visualStyle
            self.animateTitle = animateTitle
            let initialSelection = (defaultMode == .duckAI) ? Self.pickerItems[1] : Self.pickerItems[0]
            _selectedMode = State(initialValue: defaultMode)
            _pickerViewModel = StateObject(wrappedValue: ImageSegmentedPickerViewModel(
                items: Self.pickerItems,
                selectedItem: initialSelection,
                configuration: ImageSegmentedPickerConfiguration(itemContentSpacing: Metrics.queryFieldContentSpacing),
                scrollProgress: defaultMode == .duckAI ? 1 : 0,
                isScrollProgressDriven: false
            ))
        }

        // MARK: View
        var body: some View {
            VStack(spacing: Metrics.contentVerticalSpacing) {
                // Header text inside the onboarding bubble.
                Group {
                    if visualStyle == .rebranded {
                        TypingText(
                            content.title,
                            startAnimating: $rebrandedAnimateTitle,
                            onTypingFinished: handleTitleAnimationFinished
                        )
                    } else {
                        AnimatableTypingText(
                            content.title,
                            startAnimating: animateTitle,
                            onTypingFinished: handleTitleAnimationFinished
                        )
                    }
                }
                    .font(visualStyle == .rebranded ? onboardingTheme.typography.title : Font(UIFont.daxTitle3()))
                    .multilineTextAlignment(visualStyle == .rebranded ? .center : .leading)
                    .foregroundColor(visualStyle == .rebranded ? onboardingTheme.colorPalette.textPrimary : Color(designSystemColor: .textPrimary))
                    .frame(maxWidth: .infinity, alignment: visualStyle == .rebranded ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Group {
                    if content.isToggleVisible {
                        // Search / Duck.ai segmented control.
                        ImageSegmentedPickerView(viewModel: pickerViewModel)
                            .frame(width: Metrics.pickerWidth, height: Metrics.pickerHeight)
                            .padding(.vertical, Metrics.pickerVerticalPadding)
                            .frame(width: Metrics.pickerWidth, height: Metrics.pickerContainerHeight)
                        // Drive content mode (Search vs Duck.ai) from user picker selection.
                            .onChange(of: pickerViewModel.selectedItem) { [reduceMotion] selectedItem in
                                let newMode: DuckAIQueryMode = selectedItem == Self.pickerItems[1] ? .duckAI : .search
                                if reduceMotion {
                                    selectedMode = newMode
                                } else {
                                    SwiftUI.withAnimation(.easeInOut(duration: Metrics.pickerSelectionAnimationDuration)) {
                                        selectedMode = newMode
                                    }
                                }
                            }
                        // Keep picker model + visual progress in sync for programmatic/default mode changes.
                            .onChange(of: selectedMode) { selection in
                                let pickerItem = selection == .duckAI ? Self.pickerItems[1] : Self.pickerItems[0]
                                if pickerViewModel.selectedItem != pickerItem {
                                    pickerViewModel.selectItem(pickerItem)
                                }
                                pickerViewModel.updateScrollProgress(selection == .duckAI ? 1 : 0)
                            }
                            .padding(.top, titleToPickerTopPadding)
                            .padding(.bottom, Metrics.pickerBottomPadding)
                    }

                    // If toggle is not visible set a different padding to avoid text area to be too close to the title
                    let queryFieldTopPadding = content.isToggleVisible ? Metrics.queryFieldTopPadding : nil

                    // Query field + trailing action icon.
                    queryField
                        .padding(.top, queryFieldTopPadding)
                        .padding(.bottom, Metrics.queryFieldBottomPadding)
                }
                .opacity(showInteractiveControls ? 1 : 0)
                .allowsHitTesting(showInteractiveControls)

                // Delayed/staggered suggestion chips.
                if visibleSuggestionCount > 0 {
                    suggestionChips
                        .padding(.top, Metrics.fieldToFirstChipTopPadding)
                }
            }
            .opacity(isTransitioningOut ? 0 : 1)
            .onAppear {
                let initialSelection = selectedMode == .duckAI ? Self.pickerItems[1] : Self.pickerItems[0]
                pickerViewModel.selectItem(initialSelection)
                pickerViewModel.updateScrollProgress(selectedMode == .duckAI ? 1 : 0)
                query = ""
                isInputFocused = false
                visibleSuggestionCount = 0
                showInteractiveControls = false
                hasStartedEntranceSequence = false
                hasPassedInitialFocusDelay = false
                shouldFocusWhenInitialDelayPasses = false
                suggestionSequenceStarted = false
                scheduleInitialFocusGate()
                // Both styles end up in `handleTitleAnimationFinished`; only the start binding differs.
                if visualStyle == .rebranded {
                    rebrandedAnimateTitle = true
                } else {
                    animateTitle.wrappedValue = true
                }
            }
            // Fade out this content while transitioning to the selected destination.
            .animation(reduceMotion ? nil : .easeInOut(duration: Metrics.contentFadeAnimationDuration), value: isTransitioningOut)
            .animation(reduceMotion ? nil : .easeInOut(duration: Metrics.contentFadeAnimationDuration), value: showInteractiveControls)
        }

        // MARK: Style
        private var accentColor: Color {
            visualStyle == .rebranded ? Color(singleUseColor: .rebranding(.accentPrimary)) : Color(designSystemColor: .accent)
        }

        private var titleToPickerTopPadding: CGFloat {
            visualStyle == .rebranded ? Metrics.rebrandedTitleToPickerTopPadding : Metrics.legacyTitleToPickerTopPadding
        }

        private var accentSecondaryColor: Color {
            visualStyle == .rebranded ? Color(singleUseColor: .rebranding(.accentAltGlowPrimary)) : Color(designSystemColor: .accentGlowSecondary)
        }

        private var queryFieldBackgroundColor: Color {
            visualStyle == .rebranded ? onboardingTheme.colorPalette.background : Color(designSystemColor: .surface)
        }

        private var queryFieldBorderWidth: CGFloat {
            visualStyle == .rebranded ? Metrics.rebrandedQueryFieldBorderWidth : Metrics.legacyQueryFieldBorderWidth
        }

        private var initialInputFocusDelayAfterAppear: TimeInterval {
            visualStyle == .rebranded ? Metrics.rebrandedInitialInputFocusDelayAfterAppear : Metrics.legacyInitialInputFocusDelayAfterAppear
        }

        // MARK: Initial Sequencing
        private func handleTitleAnimationFinished() {
            guard !hasStartedEntranceSequence else { return }
            hasStartedEntranceSequence = true

            // Reduce Motion: skip the staggered entrance — show controls + suggestions and
            // focus the input immediately.
            if reduceMotion {
                guard !isTransitioningOut else { return }
                showInteractiveControls = true
                requestInputFocus()
                startSuggestionSequenceIfNeeded()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.controlsRevealDelayAfterTitleAnimation) {
                guard hasStartedEntranceSequence, !isTransitioningOut else { return }
                showInteractiveControls = true
                DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.keyboardFocusDelayAfterControlsReveal) {
                    guard hasStartedEntranceSequence, showInteractiveControls, !isTransitioningOut else { return }
                    requestInputFocus()
                }
                startSuggestionSequenceIfNeeded()
            }
        }

        private func scheduleInitialFocusGate() {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialInputFocusDelayAfterAppear) {
                hasPassedInitialFocusDelay = true
                if shouldFocusWhenInitialDelayPasses {
                    shouldFocusWhenInitialDelayPasses = false
                    isInputFocused = true
                }
            }
        }

        private func requestInputFocus() {
            if hasPassedInitialFocusDelay {
                isInputFocused = true
            } else {
                shouldFocusWhenInitialDelayPasses = true
            }
        }

        // MARK: Subviews
        private var queryField: some View {
            HStack(alignment: .bottom, spacing: Metrics.queryFieldContentSpacing) {
                // Text input
                OnboardingQueryField(
                    text: $query,
                    placeholder: selectedMode == .duckAI
                    ? content.aiPlaceholder
                    : content.searchPlaceholder,
                    isFocused: $isInputFocused,
                    isSingleLine: selectedMode != .duckAI,
                    onSubmit: handlePrimaryAction
                )
                .transaction { transaction in
                    // Prevent placeholder/baseline shifts from inheriting parent animations when toggling mode.
                    transaction.animation = nil
                }
                .frame(
                    height: selectedMode == .duckAI ? Metrics.multilineFieldHeight : Metrics.singleLineFieldHeight,
                    alignment: selectedMode == .duckAI ? .topLeading : .center
                )

                // Submit action button
                Button(action: handlePrimaryAction) {
                    Image(
                        uiImage: selectedMode == .duckAI
                        ? DesignSystemImages.Glyphs.Size16.arrowRight
                        : DesignSystemImages.Glyphs.Size24.findSearchSmall
                    )
                    .renderingMode(.template)
                    .foregroundColor(visualStyle == .rebranded ? accentColor : Color(designSystemColor: .icons))
                    .opacity(isPrimaryActionEnabled ? 1 : Metrics.disabledPrimaryActionOpacity)
                    .frame(width: Metrics.queryFieldActionButtonSize, height: Metrics.queryFieldActionButtonSize)
                    .offset(x: Metrics.queryFieldActionOffsetX, y: Metrics.queryFieldActionOffsetY)
                }
                .buttonStyle(.plain)
                .disabled(!isPrimaryActionEnabled)
            }
            .padding(.horizontal, Metrics.queryFieldHorizontalPadding)
            .padding(.vertical, Metrics.queryFieldVerticalPadding)
            .background(queryFieldBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.queryFieldCornerRadius)
                    .strokeBorder(accentSecondaryColor, lineWidth: queryFieldBorderWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.queryFieldCornerRadius)
                    .inset(by: Metrics.queryFieldInnerBorderInset)
                    .strokeBorder(accentColor, lineWidth: queryFieldBorderWidth)
            )
            .cornerRadius(Metrics.queryFieldCornerRadius)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: Metrics.contentFadeAnimationDuration), value: selectedMode)
        }

        private var suggestionChips: some View {
            OnboardingSuggestionChips(
                viewModel: suggestionsViewModel,
                isDuckAIMode: selectedMode == .duckAI,
                visibleCount: visibleSuggestionCount,
                visualStyle: visualStyle,
                onItemTap: { item, promptSource in
                    openSelectedExperience(prompt: item.title, autoSend: true, promptSource: promptSource)
                }
            )
        }

        private var suggestionAppearanceAnimation: Animation {
            .interpolatingSpring(
                mass: Metrics.suggestionSpringMass,
                stiffness: Metrics.suggestionSpringStiffness,
                damping: Metrics.suggestionSpringDamping,
                initialVelocity: Metrics.suggestionSpringInitialVelocity
            )
        }

        // MARK: Actions
        private func handlePrimaryAction() {
            guard isPrimaryActionEnabled else { return }
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            openSelectedExperience(
                prompt: trimmedQuery.isEmpty ? nil : trimmedQuery,
                autoSend: !trimmedQuery.isEmpty,
                promptSource: .custom
            )
        }

        private var isPrimaryActionEnabled: Bool {
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private func openSelectedExperience(prompt: String?, autoSend: Bool, promptSource: DuckAIQueryPromptSource) {
            if autoSend {
                measureQuerySubmissionAction(selectedMode, promptSource)
            }

            let preloadedSearchQuery: String? = {
                guard selectedMode != .duckAI, let searchQuery = prompt, !searchQuery.isEmpty else { return nil }
                return searchQuery
            }()

            // Start browser loading immediately so results can be ready behind the exit hold.
            if let searchQuery = preloadedSearchQuery {
                openSearchAction(searchQuery)
            }

            isInputFocused = false
            dismissKeyboard()
            startExitTransitionAction()

            let completion = {
                if selectedMode == .duckAI {
                    openAIChatAction(prompt, autoSend)
                    onModeConfirmed(.duckAI)
                } else if preloadedSearchQuery != nil {
                    onModeConfirmed(.search)
                } else {
                    isTransitioningOut = false
                }
            }

            if reduceMotion {
                isTransitioningOut = true
                completion()
            } else {
                withAnimation(.easeOut(duration: Metrics.contentFadeAnimationDuration)) {
                    isTransitioningOut = true
                } completion: {
                    completion()
                }
            }
        }

        // MARK: Suggestion Sequencing
        private func startSuggestionSequenceIfNeeded() {
            guard !suggestionSequenceStarted, showInteractiveControls else { return }
            suggestionSequenceStarted = true
            // Reduce Motion: show all suggestions at once, no staggered reveal.
            guard !reduceMotion else {
                guard !isTransitioningOut else { return }
                visibleSuggestionCount = Metrics.maxSuggestionCount
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.suggestionInitialRevealDelay) {
                guard suggestionSequenceStarted, showInteractiveControls, !isTransitioningOut else { return }
                startSuggestionRevealSequence()
            }
        }

        private func startSuggestionRevealSequence() {
            guard suggestionSequenceStarted, !isTransitioningOut else { return }
            visibleSuggestionCount = 0
            revealSuggestionsSequentially(nextIndex: 1)
        }

        private func revealSuggestionsSequentially(nextIndex: Int) {
            guard suggestionSequenceStarted, !isTransitioningOut else { return }
            guard nextIndex <= Metrics.maxSuggestionCount else { return }

            withAnimation(suggestionAppearanceAnimation) {
                visibleSuggestionCount = nextIndex
            } completion: {
                revealSuggestionsSequentially(nextIndex: nextIndex + 1)
            }
        }

        // MARK: Utilities
        @MainActor
        private func withAnimation(_ animation: Animation, _ updates: @escaping () -> Void, completion: @escaping () -> Void) {
            if #available(iOS 17, *) {
                SwiftUI.withAnimation(animation, completionCriteria: .logicallyComplete, updates) {
                    completion()
                }
            } else {
                CATransaction.begin()
                CATransaction.setCompletionBlock(completion)
                SwiftUI.withAnimation(animation, updates)
                CATransaction.commit()
            }
        }
        private func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

}

// MARK: - OnboardingQueryField
private struct OnboardingQueryField: UIViewRepresentable {
    private static let singleLineTopInset: CGFloat = 5.0 / 3.0
    private static let multiLineTopInset: CGFloat = 10.0 / 3.0

    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    let isSingleLine: Bool
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        textView.backgroundColor = .clear
        textView.font = .daxBodyRegular()
        textView.textColor = UIColor(designSystemColor: .textPrimary)

        textView.delegate = context.coordinator

        textView.isScrollEnabled = true
        textView.showsHorizontalScrollIndicator = false
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceVertical = false

        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyModeConfiguration(to: textView, isSingleLine: isSingleLine, context: context)

        context.coordinator.placeholderLabel.text = placeholder
        context.coordinator.placeholderLabel.font = textView.font
        context.coordinator.placeholderLabel.textColor = UIColor(designSystemColor: .textTertiary)
        context.coordinator.placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.addSubview(context.coordinator.placeholderLabel)

        let placeholderTopConstraint = context.coordinator.placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor)
        context.coordinator.placeholderTopConstraint = placeholderTopConstraint

        NSLayoutConstraint.activate([
            context.coordinator.placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderTopConstraint
        ])

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }

        // Update Placeholder when switching between 'Search' and 'Duck.ai' toggle
        if context.coordinator.placeholderLabel.text != placeholder {
            context.coordinator.placeholderLabel.text = placeholder
        }

        if context.coordinator.isSingleLine != isSingleLine {
            context.coordinator.isSingleLine = isSingleLine
            applyModeConfiguration(to: textView, isSingleLine: isSingleLine, context: context)
        }

        let topInset = isSingleLine ? Self.singleLineTopInset : Self.multiLineTopInset

        UIView.performWithoutAnimation {
            textView.textContainerInset = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
            context.coordinator.placeholderTopConstraint?.constant = topInset
            textView.layoutIfNeeded()
        }

        if isFocused {
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        } else if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    private func applyModeConfiguration(to textView: UITextView, isSingleLine: Bool, context: Context) {
        textView.returnKeyType = isSingleLine ? .search : .go
        textView.alwaysBounceHorizontal = isSingleLine

        if isSingleLine {
            textView.textContainer.widthTracksTextView = false
            textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: 34)
            textView.textContainer.maximumNumberOfLines = 1
            textView.textContainer.lineBreakMode = .byClipping
        } else {
            textView.textContainer.widthTracksTextView = true
            textView.textContainer.size = CGSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer.maximumNumberOfLines = 0
            textView.textContainer.lineBreakMode = .byWordWrapping
        }
        let savedSelection = textView.selectedRange
        textView.selectedRange = NSRange(location: 0, length: 0)
        DispatchQueue.main.async {
            context.coordinator.adjustContentSizeIfNeeded(textView)
            textView.selectedRange = savedSelection
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            isSingleLine: isSingleLine,
            onSubmit: onSubmit
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool

        var isSingleLine: Bool
        private let onSubmit: () -> Void

        let placeholderLabel = UILabel()
        var placeholderTopConstraint: NSLayoutConstraint?

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            isSingleLine: Bool,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            self.isSingleLine = isSingleLine
            self.onSubmit = onSubmit
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text ?? ""
            placeholderLabel.isHidden = !text.isEmpty
            adjustContentSizeIfNeeded(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if isFocused {
                DispatchQueue.main.async {
                    textView.becomeFirstResponder()
                }
            } else {
                isFocused = false
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n" {
                onSubmit()
                return false
            }

            guard isSingleLine else { return true }

            // Sanitize single-line text input to prevent line breaks.
            if replacement.contains("\n"),
               let currentText = textView.text,
               let swiftRange = Range(range, in: currentText) {

                let normalized = replacement.replacingOccurrences(of: "\n", with: " ")
                let updated = currentText.replacingCharacters(in: swiftRange, with: normalized)

                textView.text = updated
                textView.selectedRange = NSRange(location: range.location + normalized.count, length: 0)

                text = updated
                placeholderLabel.isHidden = !updated.isEmpty
                return false
            }

            return true
        }

        func adjustContentSizeIfNeeded(_ textView: UITextView) {
            guard isSingleLine, let font = textView.font else { return }

            let padding: CGFloat = 12

            let textWidth = (textView.text as NSString).size(withAttributes: [.font: font]).width + padding * 2
            textView.contentSize = CGSize(width: textWidth, height: textView.bounds.height)
        }

    }
}

// MARK: - Suggestion View Model

struct OnboardingDuckAIExperimentSuggestionsViewModel {
    private let searchSuggestionsProvider: OnboardingSuggestionsItemsProviding
    private let duckAISuggestionsProvider: OnboardingSuggestionsItemsProviding

    init(
        searchSuggestionsProvider: OnboardingSuggestionsItemsProviding = OnboardingSuggestedSearchesProvider(),
        duckAISuggestionsProvider: OnboardingSuggestionsItemsProviding = OnboardingDuckAISuggestionsProvider()
    ) {
        self.searchSuggestionsProvider = searchSuggestionsProvider
        self.duckAISuggestionsProvider = duckAISuggestionsProvider
    }

    func itemsList(for isDuckAIMode: Bool) -> [ContextualOnboardingListItem] {
        isDuckAIMode ? duckAISuggestionsProvider.list : searchSuggestionsProvider.list
    }
}


// MARK: - OnboardingSuggestionChips

private enum OnboardingSuggestionsChipsMetrics {
    static let suggestionTransitionScale: CGFloat = 0.96
    static let suggestionChipIconSize: CGSize = CGSize(width: 16, height: 16)
    static let interChipSpacingLegacy: CGFloat = 8
}

private struct OnboardingSuggestionChips: View {
    @Environment(\.onboardingTheme.contextualOnboardingMetrics) private var contextualOnboardingMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viewModel: OnboardingDuckAIExperimentSuggestionsViewModel
    let isDuckAIMode: Bool
    let visibleCount: Int
    let visualStyle: OnboardingView.DuckAIExperimentSearchContent.VisualStyle
    let onItemTap: (ContextualOnboardingListItem, DuckAIQueryPromptSource) -> Void

    // MARK: Computed Properties
    private var visibleItems: [ContextualOnboardingListItem] {
        Array(viewModel.itemsList(for: isDuckAIMode).prefix(visibleCount))
    }

    private var suggestionTransition: AnyTransition {
        if reduceMotion {
            return .identity
        }
        return .asymmetric(
            insertion: .scale(scale: OnboardingSuggestionsChipsMetrics.suggestionTransitionScale, anchor: .top).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var chipIconSize: CGSize {
        if visualStyle == .rebranded {
            return contextualOnboardingMetrics.optionsListMetrics.iconSize
        }
        return OnboardingSuggestionsChipsMetrics.suggestionChipIconSize
    }

    private var chipSpacing: CGFloat {
        if visualStyle == .rebranded {
            return contextualOnboardingMetrics.optionsListMetrics.interItemSpacing ?? OnboardingSuggestionsChipsMetrics.interChipSpacingLegacy
        }
        return OnboardingSuggestionsChipsMetrics.interChipSpacingLegacy
    }

    private func promptSource(for index: Int) -> DuckAIQueryPromptSource {
        switch index {
        case 0: return .option1
        case 1: return .option2
        case 2: return .option3
        default: return .custom
        }
    }

    // MARK: Body
    var body: some View {
        VStack(spacing: chipSpacing) {
            ForEach(Array(visibleItems.enumerated()), id: \.offset) { index, item in
                if visualStyle == .legacy {
                    legacyButton(for: item, at: index)
                } else {
                    rebrandedButton(for: item, at: index)
                }
            }
        }
    }

    // MARK: Subviews
    @ViewBuilder
    private func legacyButton(for item: ContextualOnboardingListItem, at index: Int) -> some View {
        OnboardingBorderedButton(
            content: {
                HStack {
                    Image(uiImage: item.image)
                        .frame(width: chipIconSize.width, height: chipIconSize.height)
                    Text(item.visibleTitle)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            },
            action: { handleItemTap(item, at: index) }
        )
        .transition(suggestionTransition)
    }

    @ViewBuilder
    private func rebrandedButton(for item: ContextualOnboardingListItem, at index: Int) -> some View {
        OnboardingRebranding.ContextualOnboardingListViewItem(
            item: item,
            iconSize: chipIconSize,
            action: { handleItemTap(item, at: index) }
        )
        .transition(suggestionTransition)
    }

    private func handleItemTap(_ item: ContextualOnboardingListItem, at index: Int) {
        onItemTap(item, promptSource(for: index))
    }
}
