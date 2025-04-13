//
//  DaxDialogView.swift
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

import SwiftUI
import DesignResourcesKit

// MARK: - Metrics

private enum DaxDialogMetrics {
    static let contentPadding: CGFloat = 24.0
    static let shadowRadius: CGFloat = 5.0
    static let stackSpacing: CGFloat = 8
    static let dismissButtonPadding: CGFloat = 8
    static let dismissButtonSize: CGFloat = 44

    enum DaxLogo {
        static let size: CGFloat = 54.0
        static let horizontalPadding: CGFloat = 10
    }
}

// MARK: - DaxDialog

public enum DaxDialogLogoPosition {
    case top
    case left
}

public struct DaxDialogView<Content: View>: View {

    @Environment(\.colorScheme) var colorScheme

    @State private var logoPosition: DaxDialogLogoPosition

    private let matchLogoAnimation: (id: String, namespace: Namespace.ID)?
    private let showDialogBox: Binding<Bool>
    private let cornerRadius: CGFloat
    private let arrowSize: CGSize
    private let onTapGesture: (() -> Void)?
    private let onManualDismiss: (() -> Void)?
    private let content: Content

    public init(
        logoPosition: DaxDialogLogoPosition,
        matchLogoAnimation: (String, Namespace.ID)? = nil,
        showDialogBox: Binding<Bool> = .constant(true),
        cornerRadius: CGFloat = 16.0,
        arrowSize: CGSize = .init(width: 16.0, height: 8.0),
        onTapGesture: (() -> Void)? = nil,
        onManualDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        _logoPosition = State(initialValue: logoPosition)
        self.matchLogoAnimation = matchLogoAnimation
        self.showDialogBox = showDialogBox
        self.cornerRadius = cornerRadius
        self.arrowSize = arrowSize
        self.onTapGesture = onTapGesture
        self.onManualDismiss = onManualDismiss
        self.content = content()
    }

    public var body: some View {
        Group {
            switch logoPosition {
            case .top:
                topLogoViewContentView
            case .left:
                leftLogoContentView
            }
        }
        .onTapGesture {
            onTapGesture?()
        }
    }

    private var topLogoViewContentView: some View {
        VStack(alignment: .leading, spacing: stackSpacing) {
            daxLogo
                .padding(.leading, DaxDialogMetrics.DaxLogo.horizontalPadding)

            wrappedContent
                .visibility(showDialogBox.wrappedValue ? .visible : .invisible)
        }
    }

    private var leftLogoContentView: some View {
        HStack(alignment: .top, spacing: stackSpacing) {
            daxLogo

            wrappedContent
                .visibility(showDialogBox.wrappedValue ? .visible : .invisible)
        }

    }

    private var stackSpacing: CGFloat {
        DaxDialogMetrics.stackSpacing + arrowSize.height
    }

    @ViewBuilder
    private var daxLogo: some View {
        let icon = Image("DaxIconExperiment", bundle: bundle)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: DaxDialogMetrics.DaxLogo.size, height: DaxDialogMetrics.DaxLogo.size)

        if let matchLogoAnimation {
            icon.matchedGeometryEffect(id: matchLogoAnimation.id, in: matchLogoAnimation.namespace)
        } else {
            icon
        }
    }

    @ViewBuilder
    private var wrappedContent: some View {
        let backgroundColor = Color(designSystemColor: .surface)
        let shadowColors: (Color, Color) = colorScheme == .light
        ? (.black.opacity(0.08), .black.opacity(0.1))
        : (.black.opacity(0.20), .black.opacity(0.16))

        let styledContent = content
            .padding(.all, DaxDialogMetrics.contentPadding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: shadowColors.0, radius: 16, x: 0, y: 8)
            .shadow(color: shadowColors.1, radius: 6, x: 0, y: 2)
            .overlay(
                Triangle()
                    .frame(width: arrowSize.width, height: arrowSize.height)
                    .foregroundColor(backgroundColor)
                    .rotationEffect(Angle(degrees: logoPosition == .top ? 0 : -90), anchor: .bottom)
                    .offset(arrowOffset),
                alignment: .topLeading
            )

        if #available(macOS 12.0, iOS 15.0, *) {
            styledContent
                .ifLet(onManualDismiss) { view, onDismiss in
                    view.overlay(alignment: .topTrailing) {
                        OnboardingDismissButton(action: onDismiss)
                            .alignmentGuide(.top) { $0.height / 2 - DaxDialogMetrics.dismissButtonPadding }
                            .alignmentGuide(.trailing) { $0.width / 2 + DaxDialogMetrics.dismissButtonPadding }
                    }
                }
        } else {
            ZStack(alignment: .topTrailing) {
                styledContent
                if let onDismiss = onManualDismiss {
                    OnboardingDismissButton(action: onDismiss)
                        .alignmentGuide(.top) { $0.height / 2 - DaxDialogMetrics.dismissButtonPadding }
                        .alignmentGuide(.trailing) { $0.width / 2 + DaxDialogMetrics.dismissButtonPadding }
                }
            }
        }
    }

    private var arrowOffset: CGSize {
        switch logoPosition {
        case .top:
            let leadingOffset = DaxDialogMetrics.DaxLogo.horizontalPadding + DaxDialogMetrics.DaxLogo.size / 2 - arrowSize.width / 2
            return CGSize(width: leadingOffset, height: -arrowSize.height)
        case .left:
            let topOffset = DaxDialogMetrics.DaxLogo.size / 2 - arrowSize.width / 2
            return CGSize(width: -arrowSize.height, height: topOffset)
        }
    }
}

// MARK: - Preview

#Preview("Dax Dialog Top Logo") {
    ZStack {
        Color.green.ignoresSafeArea()

        DaxDialogView(logoPosition: .top) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(verbatim: "Hi there.")

                    Text(verbatim: "Ready for a better, more private internet?")
                }
            }
        }
        .padding()
    }
}

#Preview("Dax Dialog Left Logo") {
    ZStack {
        Color.green.ignoresSafeArea()

        DaxDialogView(logoPosition: .left) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(verbatim: "Hi there.")

                    Text(verbatim: "Ready for a better, more private internet?")
                }
            }
        }
        .padding()
    }
}

struct OnboardingDismissButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var isPressed = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("Close-16", bundle: bundle)
                .foregroundColor(.primary)
                .padding(DaxDialogMetrics.dismissButtonPadding)
                .background(backgroundColor)
                .background(opacityColor)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .pressEvents {
            isPressed = true
        } onRelease: {
            isPressed = false
        }
        .shadow(color: Color(red: 0.1, green: 0.17, blue: 0.3).opacity(0.05), radius: 12, x: 0, y: 8)
        .shadow(color: Color(red: 0.17, green: 0.1, blue: 0.3).opacity(0.05), radius: 6, x: 0, y: 4)
        .shadow(color: Color(red: 0.1, green: 0.16, blue: 0.3).opacity(0.08), radius: 1, x: 0, y: 1)
        .frame(width: DaxDialogMetrics.dismissButtonSize, height: DaxDialogMetrics.dismissButtonSize)
    }

    private var backgroundColor: Color {
        switch colorScheme {
        case .light:
            Color(red: 0.98, green: 0.98, blue: 0.98)
        case .dark:
            Color(red: 0.27, green: 0.27, blue: 0.27)
        @unknown default:
            Color(red: 0.98, green: 0.98, blue: 0.98)
        }
    }

    private var opacityColor: Color {
        switch (colorScheme, isPressed, isHovering) {
        case (.light, true, _): return Color.black.opacity(0.12)
        case (.light, false, true): return Color.black.opacity(0.06)
        case (.light, false, false): return Color.clear

        case (.dark, true, _): return Color.white.opacity(0.10)
        case (.dark, false, true): return Color.white.opacity(0.06)
        case (.dark, false, false): return Color.clear

        @unknown default:
            return Color(red: 0.98, green: 0.98, blue: 0.98)
        }
    }
}

// Move this extension to `SwiftUIExtensions` package when creating it.
private extension View {

    @ViewBuilder func `ifLet`<Content: View, Value>(_ value: Value?, transform: (Self, Value) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }

    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
            )
    }

}
