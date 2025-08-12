//
//  ReportProblemFormView.swift
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
import SwiftUIExtensions
import DesignResourcesKit
import DesignResourcesKitIcons

final class ReportProblemFormViewController: NSHostingController<ReportProblemFormFlowView> {

    enum Constants {
        static let width: CGFloat = 448
        static let height: CGFloat = 560

        // Constants for the sub-categories screen
        static let detailsFormHeight: CGFloat = 356

        // Constants for thank you screen
        static let thankYouWidth: CGFloat = 448
        static let thankYouHeight: CGFloat = 232
    }

    override init(rootView: ReportProblemFormFlowView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct ReportProblemFormFlowView: View {
    @StateObject private var viewModel: ReportProblemFormViewModel

    var onClose: () -> Void
    var onSeeWhatsNew: () -> Void
    var onResize: (CGFloat, CGFloat) -> Void

    init(
        canReportBrokenSite: Bool,
        onReportBrokenSite: (() -> Void)?,
        onClose: @escaping () -> Void,
        onSeeWhatsNew: @escaping () -> Void,
        onResize: @escaping (CGFloat, CGFloat) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: ReportProblemFormViewModel(
            canReportBrokenSite: canReportBrokenSite,
            onReportBrokenSite: onReportBrokenSite
        ))
        self.onClose = onClose
        self.onSeeWhatsNew = onSeeWhatsNew
        self.onResize = onResize
    }

    var body: some View {
        Group {
            if viewModel.showThankYou {
                ThankYouView(
                    onClose: {
                        onClose()
                    },
                    onSeeWhatsNew: onSeeWhatsNew
                )
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onResize(ReportProblemFormViewController.Constants.thankYouWidth,
                                     ReportProblemFormViewController.Constants.thankYouHeight)
                        }
                    }
                }
            } else if viewModel.isShowingDetailForm {
                ProblemDetailFormView(
                    viewModel: viewModel,
                    onBack: {
                        viewModel.goBackToCategorySelection()
                    },
                    onClose: onClose,
                    onResize: onResize
                )
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onResize(ReportProblemFormViewController.Constants.width,
                                     ReportProblemFormViewController.Constants.detailsFormHeight)
                        }
                    }
                }
            } else if viewModel.isShowingCategorySelection {
                ProblemCategoriesView(
                    viewModel: viewModel,
                    onClose: onClose
                )
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onResize(ReportProblemFormViewController.Constants.width,
                                     ReportProblemFormViewController.Constants.height)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Problem Categories View

struct ProblemCategoriesView: View {
    @ObservedObject var viewModel: ReportProblemFormViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
            categoriesList()

            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header() -> some View {
        HStack(spacing: 12) {
            Image(.feedbackAsk)

            VStack(alignment: .leading, spacing: 8) {
                Text(UserText.reportBrowserProblem)
                    .systemTitle2()

                Text(UserText.reportProblemFormSubtitle)
                    .systemLabel()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding([.leading, .trailing, .bottom], 24)
    }

    @State private var hoveredCategoryId: String?

    private func shouldShowDivider(for category: ProblemCategory) -> Bool {
        let isLastItem = category.id == viewModel.availableCategories.last?.id

        if isLastItem {
            return false
        } else if hoveredCategoryId == category.id {
            return false
        } else if let previousHoveredItem = getHoveredPreviousItem {
            return previousHoveredItem.id != category.id
        } else {
            return true
        }
    }

    private var getHoveredPreviousItem: ProblemCategory? {
        guard let hoveredCategoryId = hoveredCategoryId else {
            return nil
        }

        let categories = Array(viewModel.availableCategories)

        if let selectedIndex = categories.firstIndex(where: { $0.id == hoveredCategoryId }),
           selectedIndex > 0 {
            let previousItem = categories[selectedIndex - 1]
            return previousItem
        } else {
            return nil
        }
    }

    private func categoriesList() -> some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.availableCategories.enumerated()), id: \.element.id) { _, category in
                ProblemCategoryView(
                    category: category,
                    shouldShowDivider: shouldShowDivider(for: category),
                    isTopCategory: category.id == viewModel.availableCategories.first?.id,
                    isLastCategory: category.id == viewModel.availableCategories.last?.id,
                    onCategorySelected: { selectedCategory in
                        viewModel.selectCategory(selectedCategory)
                        if selectedCategory.isReportBrokenWebsiteCategory {
                            onClose()
                        }
                    },
                    onHoverChanged: { categoryId, isHovered in
                        hoveredCategoryId = isHovered ? categoryId : nil
                    }
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.divider, lineWidth: 1)
        )
        .padding([.leading, .trailing, .bottom], 24)
    }

    private func footer() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .background(Color.divider)
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            Text(UserText.feedbackDisclaimer)
                .caption2()
                .multilineTextAlignment(.leading)
                .padding([.leading, .trailing], 24)

            Button {
                onClose()
            } label: {
                Text(UserText.cancel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DismissActionButtonStyle())
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Problem Category Row View

struct ProblemCategoryView: View {
    let category: ProblemCategory
    let shouldShowDivider: Bool
    let isTopCategory: Bool
    let isLastCategory: Bool
    var onCategorySelected: (ProblemCategory) -> Void
    var onHoverChanged: (String, Bool) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            onCategorySelected(category)
        } label: {
            HStack {
                Text(category.text)
                    .systemLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(nsImage: DesignSystemImages.Glyphs.Size16.chevronRight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.controlsFillPrimary : Color.clear)
        .if(isTopCategory) { view in
            view.cornerRadius(6, corners: [.topLeft, .topRight])
        }
        .if(isLastCategory) { view in
            view.cornerRadius(6, corners: [.bottomLeft, .bottomRight])
        }
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(category.id, hovering)
        }

        Rectangle()
            .stroke(shouldShowDivider ? Color.divider : Color.clear, lineWidth: 1)
            .frame(height: 1)
            .padding(.horizontal, 8)
    }
}

// MARK: - Problem Detail Form

struct ProblemDetailFormView: View {
    @ObservedObject var viewModel: ReportProblemFormViewModel
    var onBack: () -> Void
    var onClose: () -> Void
    var onResize: (CGFloat, CGFloat) -> Void

    @State private var pillsSectionHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
            optionsPills()

            if !viewModel.selectedOptions.isEmpty {
                userTextInput()
            }

            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.selectedOptions) { _ in
            updateDialogHeight()
        }
        .onChange(of: pillsSectionHeight) { _ in
            updateDialogHeight()
        }
    }

    // MARK: - Height Calculation

    private enum ComponentHeights {
        static let header: CGFloat = 72  // 24 padding + ~24 button/text + 24 padding
        static let textInputSection: CGFloat = 159  // Calculated from original height difference (515 - 356 = 159)
        static let footer: CGFloat = 122  // 16 spacing + 1 divider + ~10 disclaimer + 16 spacing + ~32 buttons + 16 bottom padding + ~31 button spacing
    }

    private func calculateTotalHeight() -> CGFloat {
        let baseHeight = ComponentHeights.header + ComponentHeights.footer

        // Always use the measured height of the pills section (which includes bottom padding)
        // The pills section height is dynamic based on how many rows the pills wrap into
        // Use a reasonable fallback during initial load before measurement completes
        let pillsHeight = pillsSectionHeight > 0 ? pillsSectionHeight : 80

        let textInputHeight = viewModel.selectedOptions.isEmpty ? 0 : ComponentHeights.textInputSection

        return baseHeight + pillsHeight + textInputHeight
    }

    private func updateDialogHeight() {
        DispatchQueue.main.async {
            withAnimation(.interactiveSpring) {
                let calculatedHeight = calculateTotalHeight()
                onResize(ReportProblemFormViewController.Constants.width, calculatedHeight)
            }
        }
    }

    private func header() -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                onBack()
            } label: {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.arrowLeft)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.selectedProblemCategory?.text ?? "")
                    .systemTitle2()

                Text(UserText.reportProblemFormSelectAllThatApply)
                    .systemLabel()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private func optionsPills() -> some View {
        FlexibleView(
            availableWidth: ReportProblemFormViewController.Constants.width,
            data: viewModel.availableOptions,
            spacing: 8,
            alignment: .leading
        ) { option in
            Pill(
                text: option.text,
                isSelected: viewModel.selectedOptions.contains(option.id)
            ) {
                viewModel.toggleOption(option.id)
            }
        }
        .padding([.leading, .trailing], 24)
        .padding(.bottom, 24)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        pillsSectionHeight = geometry.size.height
                        updateDialogHeight()
                    }
                    .onChange(of: geometry.size) { newSize in
                        if pillsSectionHeight != newSize.height {
                            pillsSectionHeight = newSize.height
                        }
                    }
            }
        )
    }

    private func userTextInput() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UserText.reportProblemFormTellUsMore)
                .systemLabel()

            AdaptiveTextEditor(text: $viewModel.customText)
                .textEditorStyling(isEmpty: viewModel.customText.isEmpty)
        }
        .padding([.leading, .trailing], 24)
        .padding(.bottom, 8)
    }

    private func footer() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .background(Color.divider)
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            Text(UserText.feedbackDisclaimer)
                .caption2()
                .multilineTextAlignment(.leading)
                .padding([.leading, .trailing], 24)

            HStack(spacing: 10) {
                Button {
                    onClose()
                } label: {
                    Text(UserText.cancel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DismissActionButtonStyle())

                Button {
                    viewModel.submitFeedback()
                } label: {
                    Text(UserText.submit)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.shouldEnableSubmit)
                .buttonStyle(DefaultActionButtonStyle(enabled: viewModel.shouldEnableSubmit))
            }
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Adaptive Text Editor Components

private struct AdaptiveTextEditor: View {
    @Binding var text: String

    var body: some View {
        if #available(macOS 12, *) {
            AutoFocusTextEditor(text: $text)
        } else {
            TextEditor(text: $text)
        }
    }
}

@available(macOS 12.0, *)
private struct AutoFocusTextEditor: View {
    @Binding var text: String
    @FocusState private var focusState: Bool

    var body: some View {
        TextEditor(text: $text)
            .focused($focusState)
            .onAppear {
                DispatchQueue.main.async {
                    focusState = true
                }
            }
    }
}

// MARK: - Text Editor Styling Extension

extension View {
    func textEditorStyling(isEmpty: Bool) -> some View {
        self
            .systemLabel()
            .frame(minHeight: 80)
            .padding(8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isEmpty ? Color(.separatorColor) : Color(baseColor: .blue50),
                            lineWidth: 1)
            )
            .overlay(
                Group {
                    if isEmpty {
                        HStack {
                            VStack {
                                HStack {
                                    Text(UserText.reportProblemFormPlaceholder)
                                        .systemLabel(color: .textTertiary)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding(11)
                        }
                    }
                }
            )
    }
}
