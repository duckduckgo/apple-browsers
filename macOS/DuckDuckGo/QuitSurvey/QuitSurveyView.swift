//
//  QuitSurveyView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import SwiftUIExtensions

// MARK: - View Controller

final class QuitSurveyViewController: NSHostingController<QuitSurveyFlowView> {

    enum Constants {
        static let initialWidth: CGFloat = 400
        static let initialHeight: CGFloat = 200
        static let positiveWidth: CGFloat = 400
        static let positiveHeight: CGFloat = 160
        static let negativeWidth: CGFloat = 448
        static let negativeBaseHeight: CGFloat = 356
    }

    override init(rootView: QuitSurveyFlowView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Flow View

struct QuitSurveyFlowView: View {
    @StateObject private var viewModel: QuitSurveyViewModel
    var onResize: ((CGFloat, CGFloat) -> Void)?

    init(
        onQuit: @escaping () -> Void,
        onResize: ((CGFloat, CGFloat) -> Void)? = nil
    ) {
        self._viewModel = StateObject(wrappedValue: QuitSurveyViewModel(
            onQuit: onQuit
        ))
        self.onResize = onResize
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .initialQuestion:
                QuitSurveyInitialView(viewModel: viewModel)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onResize?(QuitSurveyViewController.Constants.initialWidth,
                                     QuitSurveyViewController.Constants.initialHeight)
                        }
                    }

            case .positiveResponse:
                QuitSurveyPositiveView(viewModel: viewModel)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onResize?(QuitSurveyViewController.Constants.positiveWidth,
                                     QuitSurveyViewController.Constants.positiveHeight)
                        }
                    }

            case .negativeFeedback:
                QuitSurveyNegativeView(viewModel: viewModel, onResize: onResize)
            }
        }
    }
}

// MARK: - Initial Question View

private struct QuitSurveyInitialView: View {
    @ObservedObject var viewModel: QuitSurveyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
            responseOptions()
            footer()
        }
        .frame(width: QuitSurveyViewController.Constants.initialWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func header() -> some View {
        HStack(spacing: 12) {
            Image(.daxResponse48)

            Text(UserText.quitSurveyInitialQuestion)
                .systemTitle2()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding([.leading, .trailing, .bottom], 24)
    }

    private func responseOptions() -> some View {
        VStack(spacing: 0) {
            QuitSurveyOptionRow(
                icon: DesignSystemImages.Glyphs.Size12.thumbsUp,
                text: UserText.quitSurveyPositiveOption,
                showChevron: true,
                isTopRow: true,
                isBottomRow: false,
                action: { viewModel.selectPositiveResponse() }
            )

            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 1)
                .padding(.horizontal, 8)

            QuitSurveyOptionRow(
                icon: DesignSystemImages.Glyphs.Size12.thumbsDown,
                text: UserText.quitSurveyNegativeOption,
                showChevron: true,
                isTopRow: false,
                isBottomRow: true,
                action: { viewModel.selectNegativeResponse() }
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .padding([.leading, .trailing], 24)
        .padding(.bottom, 16)
    }

    private func footer() -> some View {
        Button {
            viewModel.closeAndQuit()
        } label: {
            Text(UserText.quitSurveyCloseAndQuit)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DefaultActionButtonStyle(enabled: true))
        .padding([.leading, .trailing], 24)
        .padding(.bottom, 16)
    }
}

// MARK: - Option Row

private struct QuitSurveyOptionRow: View {
    let icon: NSImage?
    let text: String
    let showChevron: Bool
    let isTopRow: Bool
    let isBottomRow: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(nsImage: icon)
                }

                Text(text)
                    .systemLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showChevron {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.chevronRight)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color(designSystemColor: .controlsFillPrimary) : Color.clear)
        .if(isTopRow) { view in
            view.cornerRadius(6, corners: [.topLeft, .topRight])
        }
        .if(isBottomRow) { view in
            view.cornerRadius(6, corners: [.bottomLeft, .bottomRight])
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Positive Response View

private struct QuitSurveyPositiveView: View {
    @ObservedObject var viewModel: QuitSurveyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header()

            Text(UserText.quitSurveyAutoQuitMessage(seconds: viewModel.autoQuitCountdown))
                .systemLabel(color: .textSecondary)
                .padding([.leading, .trailing], 24)

            Button {
                viewModel.quit()
            } label: {
                Text(UserText.quitSurveyQuitNow)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: true))
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
        }
        .frame(width: QuitSurveyViewController.Constants.positiveWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func header() -> some View {
        HStack(spacing: 12) {
            Image(.duckDuckGoResponseHeart)

            Text(UserText.quitSurveyPositiveTitle)
                .systemTitle2()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding([.leading, .trailing], 24)
    }
}

// MARK: - Negative Feedback View

private struct QuitSurveyNegativeView: View {
    @ObservedObject var viewModel: QuitSurveyViewModel
    var onResize: ((CGFloat, CGFloat) -> Void)?

    @State private var pillsSectionHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
            optionsPills()

            if viewModel.shouldShowTextInput {
                userTextInput()
            }

            footer()
        }
        .frame(width: QuitSurveyViewController.Constants.negativeWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: viewModel.selectedOptions) { _ in
            updateDialogHeight()
        }
        .onChange(of: pillsSectionHeight) { _ in
            updateDialogHeight()
        }
        .onAppear {
            updateDialogHeight()
        }
    }

    // MARK: - Height Calculation

    private enum ComponentHeights {
        static let header: CGFloat = 72
        static let textInputSection: CGFloat = 159
        static let footer: CGFloat = 122
    }

    private func calculateTotalHeight() -> CGFloat {
        let baseHeight = ComponentHeights.header + ComponentHeights.footer
        let pillsHeight = pillsSectionHeight > 0 ? pillsSectionHeight : 80
        let textInputHeight = viewModel.shouldShowTextInput ? ComponentHeights.textInputSection : 0

        return baseHeight + pillsHeight + textInputHeight
    }

    private func updateDialogHeight() {
        DispatchQueue.main.async {
            withAnimation(.interactiveSpring) {
                let calculatedHeight = calculateTotalHeight()
                onResize?(QuitSurveyViewController.Constants.negativeWidth, calculatedHeight)
            }
        }
    }

    private func header() -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                viewModel.goBack()
            } label: {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.arrowLeft)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text(UserText.quitSurveyNegativeTitle)
                    .systemTitle2()

                Text(UserText.quitSurveySelectAllThatApply)
                    .systemLabel()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private func optionsPills() -> some View {
        let horizontalPadding: CGFloat = 24
        return FlexibleView(
            availableWidth: QuitSurveyViewController.Constants.negativeWidth - (horizontalPadding * 2),
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
        .padding([.leading, .trailing], horizontalPadding)
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
            Text(UserText.quitSurveyTellUsMore)
                .systemLabel()

            Text(UserText.quitSurveyTellUsMoreHint)
                .caption2()

            TextEditor(text: $viewModel.feedbackText)
                .systemLabel()
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(viewModel.feedbackText.isEmpty ? Color(.separatorColor) : Color(baseColor: .blue50),
                                lineWidth: 1)
                )
                .overlay(
                    Group {
                        if viewModel.feedbackText.isEmpty {
                            HStack {
                                VStack {
                                    HStack {
                                        Text(UserText.quitSurveyTextPlaceholder)
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
        .padding([.leading, .trailing], 24)
        .padding(.bottom, 8)
    }

    private func footer() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .background(Color(.separatorColor))
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            Text(UserText.quitSurveyDisclaimer)
                .caption2()
                .multilineTextAlignment(.leading)
                .padding([.leading, .trailing], 24)

            Button {
                viewModel.quit()
            } label: {
                Text(UserText.quitSurveySubmitAndQuit)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.shouldEnableSubmit)
            .buttonStyle(DefaultActionButtonStyle(enabled: viewModel.shouldEnableSubmit))
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct QuitSurveyView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            QuitSurveyFlowView(onQuit: {})
                .frame(width: 400, height: 200)
                .previewDisplayName("Initial Question")
        }
    }
}
#endif
