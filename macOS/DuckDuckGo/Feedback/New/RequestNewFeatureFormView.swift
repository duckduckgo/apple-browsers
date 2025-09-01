//
//  RequestNewFeatureFormView.swift
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

final class RequestNewFeatureFormViewController: NSHostingController<RequestNewFeatureFormFlowView> {

    enum Constants {
        static let width: CGFloat = 448
        static let height: CGFloat = 540

        // Constants for thank you screen
        static let thankYouWidth: CGFloat = 448
        static let thankYouHeight: CGFloat = 232
    }

    override init(rootView: RequestNewFeatureFormFlowView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct RequestNewFeatureFormFlowView: View {
    @State private var showThankYou = false
    var onClose: () -> Void
    var onSeeWhatsNew: () -> Void
    var onResize: (CGFloat, CGFloat) -> Void

    var body: some View {
        Group {
            if showThankYou {
                ThankYouView(
                    onClose: onClose,
                    onSeeWhatsNew: onSeeWhatsNew,
                )
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onResize(RequestNewFeatureFormViewController.Constants.thankYouWidth,
                                     RequestNewFeatureFormViewController.Constants.thankYouHeight)
                        }
                    }
                }
            } else {
                RequestNewFeatureFormView(
                    onSubmit: {
                        showThankYou = true
                    },
                    onClose: onClose,
                    onResize: onResize
                )
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            // Initial height calculation will be handled by the view's updateDialogHeight()
                            // We don't need to set a fixed height here anymore
                        }
                    }
                }
            }
        }
    }
}

struct RequestNewFeatureFormView: View {
    @ObservedObject var viewModel: RequestNewFeatureViewModel = .init()

    var onSubmit: () -> Void
    var onClose: () -> Void
    var onResize: (CGFloat, CGFloat) -> Void

    @State private var pillsSectionHeight: CGFloat = 0
    @State private var incognitoInfoHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
            featurePills()

            if viewModel.shouldShowIncognitoInfo {
                incognitoInfoSection()
            }

            userTextInput()
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.selectedFeatures) { _ in
            updateDialogHeight()
        }
        .onChange(of: pillsSectionHeight) { _ in
            updateDialogHeight()
        }
        .onChange(of: incognitoInfoHeight) { _ in
            updateDialogHeight()
        }
    }

    // MARK: - Height Calculation

    private enum ComponentHeights {
        static let header: CGFloat = 72  // 24 padding + ~24 button/text + 24 padding
        static let textInputSection: CGFloat = 159  // Same as problem form
        static let footer: CGFloat = 122  // Same as problem form structure
    }

    private func calculateTotalHeight() -> CGFloat {
        let baseHeight = ComponentHeights.header + ComponentHeights.textInputSection + ComponentHeights.footer

        // Always use the measured height of the pills section (which includes bottom padding)
        // Use a reasonable fallback during initial load before measurement completes
        let pillsHeight = pillsSectionHeight > 0 ? pillsSectionHeight : 100

        // Add incognito info box height if visible
        let incognitoHeight = viewModel.shouldShowIncognitoInfo ? (incognitoInfoHeight > 0 ? incognitoInfoHeight : 80) : 0

        return baseHeight + pillsHeight + incognitoHeight
    }

    private func updateDialogHeight() {
        DispatchQueue.main.async {
            withAnimation(.interactiveSpring) {
                let calculatedHeight = calculateTotalHeight()
                onResize(RequestNewFeatureFormViewController.Constants.width, calculatedHeight)
            }
        }
    }

    private func header() -> some View {
        HStack(spacing: 12) {
            Image(.feedbackAsk)

            VStack(alignment: .leading, spacing: 8) {

                Text(UserText.requestNewFeatureFormTitle)
                    .systemTitle2()

                Text(UserText.requestNewFeatureFormSelectAllThatApply)
                    .systemLabel()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding([.leading, .trailing, .bottom], 24)
    }

    private func featurePills() -> some View {
        FlexibleView(
            availableWidth: RequestNewFeatureFormViewController.Constants.width,
            data: viewModel.availableFeatures,
            spacing: 8,
            alignment: .leading
        ) { feature in
            Pill(
                text: feature.text,
                isSelected: viewModel.selectedFeatures.contains(feature.id)
            ) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.toggleFeature(feature.id)
                }
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

    private func incognitoInfoSection() -> some View {
        IncognitoInfoBox()
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
            .transition(.opacity)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            incognitoInfoHeight = geometry.size.height
                            updateDialogHeight()
                        }
                        .onChange(of: geometry.size) { newSize in
                            if incognitoInfoHeight != newSize.height {
                                incognitoInfoHeight = newSize.height
                            }
                        }
                }
            )
    }

    private func userTextInput() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UserText.requestNewFeatureFormCustomIdea)
                .systemLabel()

            TextEditor(text: $viewModel.customFeatureText)
                .systemLabel()
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(viewModel.customFeatureText.isEmpty ? Color(.separatorColor) : Color(baseColor: .blue50),
                                lineWidth: 1)
                )
                .overlay(
                    Group {
                        if viewModel.customFeatureText.isEmpty {
                            HStack {
                                VStack {
                                    HStack {
                                        Text(UserText.requestNewFeatureFormPlaceholder)
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
        VStack(spacing: 16) {
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
                    onSubmit()
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

private struct IncognitoInfoBox: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: DesignSystemImages.Color.Size16.infoFeedback)

            VStack(alignment: .leading, spacing: 4) {
                Text(UserText.incognitoInfoBoxTitle)
                    .body()

                Text(UserText.incognitoInfoBoxDescription)
                    .systemLabel(color: .textSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.toneShade), lineWidth: 1)
        )
    }
}
