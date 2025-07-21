//
//  NewFeedbackFormView.swift
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
import Lottie

final class NewFeedbackFormViewController: NSHostingController<FeedbackFlowView> {

    enum Constants {
        static let width: CGFloat = 448
        static let height: CGFloat = 540

        // Constants for thank you screen
        static let thankYouWidth: CGFloat = 448
        static let thankYouHeight: CGFloat = 232
    }

    override init(rootView: FeedbackFlowView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct FeedbackFlowView: View {
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
                            onResize(NewFeedbackFormViewController.Constants.thankYouWidth,
                                     NewFeedbackFormViewController.Constants.thankYouHeight)
                        }
                    }
                }
            } else {
                NewFeedbackFormView(onSubmit: {
                    showThankYou = true
                }, onClose: onClose)
            }
        }
    }
}

struct NewFeedbackFormView: View {
    @State private var selectedFeatures: Set<String> = []
    @State private var customFeatureText: String = ""

    var onSubmit: () -> Void
    var onClose: () -> Void

    let availableFeatures = [
        "Advanced ad blocking",
        "AI support",
        "Cast video/audio",
        "Customize browser theme",
        "Dark mode on all sites",
        "Import bookmarks folders",
        "Import history",
        "Incognito",
        "Move browser buttons",
        "New tab page widgets",
        "Password manager extensions",
        "Picture-in-picture",
        "Reader mode",
        "Tab groups",
        "User profiles",
        "Vertical tabs",
        "Website translation"
    ].shuffled().prefix(12)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                // Header
                HStack(spacing: 12) {
                    Image(.feedbackAsk)

                    VStack(alignment: .leading, spacing: 8) {

                        Text("Request a New Feature")
                            .systemTitle2()

                        Text("Select all that apply")
                            .systemLabel()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)
                .padding([.leading, .trailing, .bottom], 24)

                // Feature selection pills
                FlexibleView(
                    availableWidth: NewFeedbackFormViewController.Constants.width,
                    data: availableFeatures,
                    spacing: 8,
                    alignment: .leading
                ) { feature in
                    FeaturePill(
                        text: feature,
                        isSelected: selectedFeatures.contains(feature)
                    ) {
                        toggleFeature(feature)
                    }
                }
                .padding([.leading, .trailing], 24)
                .padding(.bottom, 24)

                if selectedFeatures.contains("Incognito") {
                    IncognitoInfoBox()
                        .padding([.leading, .trailing], 24)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }

                // Custom feature input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Or share your own feature idea")
                        .systemLabel()

                    TextEditor(text: $customFeatureText)
                        .systemLabel()
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(customFeatureText.isEmpty ? Color(.separatorColor) : Color(baseColor: .blue50),
                                        lineWidth: 1)
                        )
                        .overlay(
                            Group {
                                if customFeatureText.isEmpty {
                                    HStack {
                                        VStack {
                                            HStack {
                                                Text("The more details you share, the better!")
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

            // Footer
            VStack(spacing: 16) {
                Divider()
                    .background(Color(baseColor: .gray20))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)

                Text("Reports sent to DuckDuckGo are 100% anonymous and only include your message, the DuckDuckGo browser version, and your macOS version.")
                    .caption2()
                    .multilineTextAlignment(.leading)
                    .padding([.leading, .trailing], 24)

                HStack(spacing: 10) {
                    Button {
                        onClose()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DismissActionButtonStyle())

                    Button {
                        onSubmit()
                    } label: {
                        Text("Submit")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DefaultActionButtonStyle(enabled: shouldEnableSubmit))
                }
                .padding([.leading, .trailing], 24)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var shouldEnableSubmit: Bool {
        !selectedFeatures.isEmpty || !customFeatureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleFeature(_ feature: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if selectedFeatures.contains(feature) {
                selectedFeatures.remove(feature)
            } else {
                selectedFeatures.insert(feature)
            }
        }
    }
}

private struct DaxHeartAnimation: NSViewRepresentable {
    private let animation: LottieAnimation?
    private let animationView = LottieAnimationView()

    init() {
        self.animation = LottieAnimation.named("pictogramDaxHeart")
    }

    func makeNSView(context: Context) -> some NSView {
        let container = NSView()
        animationView.animation = animation
        animationView.contentMode = .scaleAspectFit
        animationView.clipsToBounds = false
        animationView.loopMode = .playOnce

        container.addSubview(animationView)
        animationView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            animationView.heightAnchor.constraint(equalToConstant: 64),
            animationView.widthAnchor.constraint(equalToConstant: 64),
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        animationView.play()

        return container
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
    }
}

struct ThankYouView: View {
    var onClose: () -> Void
    var onSeeWhatsNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack(spacing: 12) {
                DaxHeartAnimation()
                    .frame(width: 64, height: 64)

                Text("Thanks for your feedback!")
                    .systemTitle2()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding([.leading, .trailing], 24)

            // Link section
            VStack(alignment: .leading, spacing: 16) {
                Text("Feedback like yours directly influences our product updates and improvements.")
                    .systemLabel(color: .textSecondary)
                    .multilineText()
                    .multilineTextAlignment(.leading)
                    .padding([.leading, .trailing], 24)

                Button {
                    onSeeWhatsNew()
                } label: {
                    HStack(spacing: 3) {
                        Text("See what's new in DuckDuckGo")
                            .systemLabel(color: .init(baseColor: .blue60))

                        Image(nsImage: DesignSystemImages.Glyphs.Size12.open)
                            .foregroundColor(.init(baseColor: .blue60))
                    }
                }
                .buttonStyle(.plain)
                .padding([.leading, .trailing], 24)

                Spacer()

                Divider()
                    .background(Color(baseColor: .gray20))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)

                // Close button
                Button {
                    onClose()
                } label: {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DismissActionButtonStyle())
                .padding([.leading, .trailing], 24)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeaturePill: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .systemLabel(color: isSelected || isHovered ? .init(baseColor: .blue60) : .textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(maxHeight: 32)
        .buttonStyle(FeaturePillButtonStyle(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct FeaturePillButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor(configuration: configuration), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if isSelected {
            return .init(baseColor: .blue0)
        } else {
            if configuration.isPressed {
                return .init(baseColor: .blue0).opacity(0.56)
            } else if isHovered {
                return .init(baseColor: .blue0).opacity(0.48)
            } else {
                return Color(.controlBackgroundColor)
            }
        }
    }

    private func borderColor(configuration: Configuration) -> Color {
        if isSelected {
            return .init(baseColor: .blue40)
        } else {
            if configuration.isPressed {
                return .init(baseColor: .blue40).opacity(0.8)
            } else if isHovered {
                return .init(baseColor: .blue40).opacity(0.64)
            } else {
                return Color(.separatorColor)
            }
        }
    }
}

struct FlexibleView<Data: Collection, Content: View>: View where Data.Element: Hashable {
    let availableWidth: CGFloat
    let data: Data
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Data.Element) -> Content
    @State private var elementsSize: [Data.Element: CGSize] = [:]

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(computeRows(), id: \.self) { rowElements in
                HStack(spacing: spacing) {
                    ForEach(rowElements, id: \.self) { element in
                        content(element)
                            .fixedSize()
                            .readSize { size in
                                elementsSize[element] = size
                            }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    func computeRows() -> [[Data.Element]] {
        var rows: [[Data.Element]] = [[]]
        var currentRowWidth: CGFloat = 0

        for element in data {
            let elementSize = elementsSize[element, default: CGSize(width: availableWidth, height: 1)]

            if currentRowWidth + elementSize.width + spacing > availableWidth {
                rows.append([element])
                currentRowWidth = elementSize.width
            } else {
                rows[rows.count - 1].append(element)
                currentRowWidth += elementSize.width + spacing
            }
        }

        return rows
    }
}

extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

extension View {
    func systemLabel(color: Color = .textPrimary) -> some View {
        self
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(color)
    }

    func systemTitle2(color: Color = .textPrimary) -> some View {
        self
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(color)
    }

    func caption2(color: Color = .textSecondary) -> some View {
        self
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(color)
    }

    func body(color: Color = .textPrimary) -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}

struct IncognitoInfoBox: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: DesignSystemImages.Color.Size16.infoFeedback)

            VStack(alignment: .leading, spacing: 4) {
                Text("Have you tried our Fire Window?")
                    .body()

                Text("Open the browser menu and select **New Fire Window** to browse without saving local history, and automatically burn data when you close the window.")
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

#Preview {
    NewFeedbackFormView(onSubmit: { }, onClose: { })
}

#Preview("Thank You View") {
    ThankYouView(onClose: { }, onSeeWhatsNew: { })
}
