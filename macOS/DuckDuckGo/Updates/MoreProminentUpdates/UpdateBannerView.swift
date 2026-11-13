//
//  UpdateBannerView.swift
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

import AppKit
import AppUpdaterShared
import DesignResourcesKit
import SwiftUI

/// Prominent update prompt shown at the top of the browser menu.
struct UpdateBannerView: View {

    enum Style {
        /// Single pill-shaped row.
        case row(title: String)
        /// Illustrated card.
        case card
    }

    let style: Style
    let version: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch style {
            case .row(let title):
                row(title: title)
            case .card:
                card
            }
        }
        .buttonStyle(UpdateBannerButtonStyle())
        // The design keeps the banner's light appearance in dark mode too.
        .environment(\.colorScheme, .light)
    }

    private func row(title: String) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                UpdateBannerIcon()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    UpdateBannerText(title, style: .title)
                    UpdateBannerText("• \(version)", style: .detail)
                }
            }
            Spacer(minLength: 8)
            UpdateBannerButtonLabel(title: buttonTitle)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color(designSystemColor: .accentPrimary)))
        .contentShape(Capsule())
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                UpdateBannerIcon()
                UpdateBannerText(UserText.updateBannerCardTitle, style: .title)
            }
            UpdateBannerButtonLabel(title: buttonTitle)
            UpdateBannerText(version, style: .detail)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            Image(.updateBannerIllustration)
                .frame(width: 224, height: 114)
        }
        .background(Color(designSystemColor: .accentPrimary))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct UpdateBannerText: View {

    enum Style {
        case title
        case detail
    }

    private let text: String
    private let style: Style

    init(_ text: String, style: Style) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(style == .title ? .system(size: 13, weight: .medium) : .system(size: 11))
            .tracking(style == .title ? MoreProminentUpdatesTypography.titleTracking : 0)
            .foregroundColor(Color(designSystemColor: style == .title ? .accentContentPrimary : .accentContentSecondary))
            .lineLimit(1)
            .frame(height: style == .title ? 13 : 11)
    }
}

private struct UpdateBannerIcon: View {

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(designSystemColor: .accentSecondary))
            UpArrow()
                .stroke(Color(designSystemColor: .accentContentPrimary),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 20, height: 20)
    }

    private struct UpArrow: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / 20
            var path = Path()
            path.move(to: CGPoint(x: 10, y: 13.25))
            path.addLine(to: CGPoint(x: 10, y: 6.75))
            path.move(to: CGPoint(x: 7.5, y: 9.25))
            path.addLine(to: CGPoint(x: 10, y: 6.75))
            path.addLine(to: CGPoint(x: 12.5, y: 9.25))
            return path.applying(CGAffineTransform(scaleX: scale, y: scale))
        }
    }
}

/// Makes the whole banner one button. The pill inside it highlights when the banner is hovered or pressed.
private struct UpdateBannerButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        UpdateBannerButtonBody(configuration: configuration)
    }
}

private struct UpdateBannerButtonBody: View {

    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .environment(\.updateBannerHighlightOpacity, configuration.isPressed ? 0.2 : (isHovered ? 0.1 : 0))
            .onHover { isHovered = $0 }
    }
}

private struct UpdateBannerButtonLabel: View {

    let title: String

    @Environment(\.updateBannerHighlightOpacity) private var highlightOpacity

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .foregroundColor(Color(designSystemColor: .accentContentPrimary))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                // The design uses the dark appearance's secondary accent, which is lighter than the light one.
                Capsule()
                    .fill(Color(designSystemColor: .accentSecondary))
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                Capsule()
                    .fill(Color(designSystemColor: .accentContentPrimary).opacity(highlightOpacity))
            )
    }
}

private struct UpdateBannerHighlightOpacityKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

private extension EnvironmentValues {
    var updateBannerHighlightOpacity: Double {
        get { self[UpdateBannerHighlightOpacityKey.self] }
        set { self[UpdateBannerHighlightOpacityKey.self] = newValue }
    }
}

extension UpdateBannerView {

    private enum MenuItemLayout {
        /// The menu's own 5pt content inset plus the design's 8pt margin around the banner.
        static let horizontalInset: CGFloat = 13
        static let verticalInset: CGFloat = 8
        static let minimumWidth: CGFloat = 334
    }

    /// Hosts the banner with the insets it needs as an `NSMenuItem` view.
    func embeddedInMenuItemView() -> NSView {
        let hostingView = NSHostingView(rootView: self
            .frame(minWidth: MenuItemLayout.minimumWidth)
            .padding(.horizontal, MenuItemLayout.horizontalInset)
            .padding(.vertical, MenuItemLayout.verticalInset))
        hostingView.frame.size = hostingView.fittingSize
        hostingView.autoresizingMask = [.width]
        return hostingView
    }
}

extension UpdateController {

    /// "Restart Now" when a Sparkle update has downloaded and is waiting for a restart, otherwise "Update Now".
    var updatePromptButtonTitle: String {
        (self as? any SparkleUpdateControlling)?.isAtRestartCheckpoint == true ? UserText.updatePromptRestartButton : UserText.updatePromptUpdateButton
    }

    /// App Store builds can't tell whether the update has downloaded, so they say "Update available".
    var updateBannerRowTitle: String {
        self is any SparkleUpdateControlling ? UserText.updateBannerRowReadyTitle : UserText.updateBannerRowAvailableTitle
    }

    var updateBannerButtonTitle: String {
        self is any SparkleUpdateControlling ? updatePromptButtonTitle : UserText.updateBannerOpenAppStoreButton
    }

    /// Opens the release notes to show progress when a Sparkle update still has to download, otherwise runs the update.
    func runUpdateFromPrompt() {
        if let sparkleUpdateController = self as? any SparkleUpdateControlling, !sparkleUpdateController.isAtRestartCheckpoint {
            sparkleUpdateController.runUpdateFromMenuItem()
        } else {
            runUpdate()
        }
    }
}

#Preview("Row") {
    UpdateBannerView(style: .row(title: UserText.updateBannerRowReadyTitle), version: "1.301.2", buttonTitle: UserText.updatePromptRestartButton) {}
        .frame(width: 334)
        .padding()
}

#Preview("Card") {
    UpdateBannerView(style: .card, version: "1.301.2", buttonTitle: UserText.updateBannerOpenAppStoreButton) {}
        .frame(width: 334)
        .padding()
}
