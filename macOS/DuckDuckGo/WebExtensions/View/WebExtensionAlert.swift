//
//  WebExtensionAlert.swift
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
import DesignResourcesKit
import SwiftUI
import SwiftUIExtensions

/// Asks the user to confirm an extension action.
struct WebExtensionAlert: View {

    struct Configuration {
        enum LeadingButton {
            case cancel(String)
            case secondary(String)
        }

        enum Icon {
            case extensionIcon(NSImage)
            case illustration(NSImage)
        }

        enum Checkbox: Equatable {
            case option(String, toolTip: String?)
            case suppression(String)
        }

        let icon: Icon?
        let title: String
        var message: String?
        var messageColor: DesignSystemColor = .textSecondary
        var details: [String] = []
        var checkbox: Checkbox?
        let confirmTitle: String
        let leadingButton: LeadingButton
    }

    enum Response {
        case cancelled
        case secondary(isChecked: Bool)
        case confirmed(isChecked: Bool)
    }

    private enum Constants {
        static let width: CGFloat = 406
        // Matches the corner radius AppKit gives the sheet window.
        static let cornerRadius: CGFloat = 16
        static let padding: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let contentSpacing: CGFloat = 12
        static let contentHorizontalPadding: CGFloat = 12
        static let contentBottomPadding: CGFloat = 16
        static let iconSize: CGFloat = 48
        static let illustrationSize: CGFloat = 72
        static let contentHorizontalPaddingWithIllustration: CGFloat = 4
        static let suppressionCheckboxTopPadding: CGFloat = 4
        static let iconInset: CGFloat = 28
        static let iconTitleSpacing: CGFloat = 28
        static let titleLeadingOffset: CGFloat = 8
        static let bulletSpacing: CGFloat = 4
        static let buttonSpacing: CGFloat = 8
        static let buttonHeight: CGFloat = 28
    }

    private let configuration: Configuration
    private var onResponse: (Response) -> Void
    @ObservedObject private var themeManager: ThemeManager
    @State private var isChecked = false
    @State private var hasResponded = false

    init(configuration: Configuration, themeManager: ThemeManager, onResponse: @escaping (Response) -> Void) {
        self.configuration = configuration
        self.themeManager = themeManager
        self.onResponse = onResponse
    }

    private var palette: DesignResourcesKit.ColorPalette {
        themeManager.designColorPalette
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            switch configuration.icon {
            case .extensionIcon(let icon):
                iconImage(icon, size: Constants.iconSize)
                    .padding([.top, .leading], Constants.iconInset - Constants.padding)
                    .padding(.bottom, Constants.iconTitleSpacing - Constants.sectionSpacing)
            case .illustration(let image):
                iconImage(image, size: Constants.illustrationSize)
            case nil:
                EmptyView()
            }

            content

            if case .option(let title, let toolTip) = configuration.checkbox {
                Toggle(title, isOn: $isChecked)
                    .toggleStyle(.checkbox)
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                    .help(toolTip ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            buttons
        }
        .padding(Constants.padding)
        .frame(width: Constants.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: Constants.cornerRadius)
            .fill(Color(designSystemColor: .surfacePrimary, palette: palette)))
    }

    @MainActor
    func show(in window: NSWindow) {
        let sheet = WebExtensionAlertWindow()
        var alert = self
        alert.onResponse = { [weak sheet] response in
            if let sheet {
                sheet.sheetParent?.endSheet(sheet)
            }
            onResponse(response)
        }
        sheet.contentView = NSHostingView(rootView: alert)
        window.beginSheet(sheet)
    }

    @MainActor
    static func present(_ configuration: Configuration, themeManager: ThemeManager, in window: NSWindow) async -> Response {
        await withCheckedContinuation { continuation in
            WebExtensionAlert(configuration: configuration, themeManager: themeManager, onResponse: continuation.resume(returning:))
                .show(in: window)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            Text(configuration.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                .multilineTextAlignment(.leading)
                .fixMultilineScrollableText()

            if let message = configuration.message {
                messageText(message)
            }

            if !configuration.details.isEmpty {
                detailsList
            }

            if case .suppression(let title) = configuration.checkbox {
                Toggle(isOn: $isChecked) {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
                }
                .toggleStyle(.checkbox)
                .padding(.top, Constants.suppressionCheckboxTopPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, contentLeadingPadding)
        .padding(.trailing, contentTrailingPadding)
        .padding(.bottom, Constants.contentBottomPadding)
    }

    private var contentLeadingPadding: CGFloat {
        if case .illustration = configuration.icon {
            return Constants.contentHorizontalPaddingWithIllustration
        }
        return Constants.contentHorizontalPadding - Constants.titleLeadingOffset
    }

    private var contentTrailingPadding: CGFloat {
        if case .illustration = configuration.icon {
            return Constants.contentHorizontalPaddingWithIllustration
        }
        return Constants.contentHorizontalPadding
    }

    private func iconImage(_ image: NSImage, size: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private func messageText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(Color(designSystemColor: configuration.messageColor, palette: palette))
            .multilineTextAlignment(.leading)
            .fixMultilineScrollableText()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(configuration.details.enumerated()), id: \.offset) { _, detail in
                HStack(alignment: .firstTextBaseline, spacing: Constants.bulletSpacing) {
                    Text(verbatim: "•")
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
                    messageText(detail)
                }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: Constants.buttonSpacing) {
            leadingButton

            Button {
                respond(.confirmed(isChecked: isChecked))
            } label: {
                Text(configuration.confirmTitle)
                    .frame(maxWidth: .infinity)
                    .frame(height: Constants.buttonHeight)
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0, stateColors: .themedActionButton, pillShape: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var leadingButton: some View {
        switch configuration.leadingButton {
        case .cancel(let title):
            dismissStyleButton(title, response: .cancelled)
                .keyboardShortcut(.cancelAction)
        case .secondary(let title):
            dismissStyleButton(title, response: .secondary(isChecked: isChecked))
        }
    }

    private func dismissStyleButton(_ title: String, response: Response) -> some View {
        Button {
            respond(response)
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .frame(height: Constants.buttonHeight)
        }
        .buttonStyle(DismissActionButtonStyle(topPadding: 0, bottomPadding: 0, pillShape: true, stateColors: .themedDismissButton))
    }

    private func respond(_ response: Response) {
        // A second key press can arrive before the sheet finishes closing.
        guard !hasResponded else { return }
        hasResponded = true
        onResponse(response)
    }
}

/// A borderless, transparent sheet, so the alert draws its own rounded corners.
private final class WebExtensionAlertWindow: NSWindow {

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    // Borderless windows can't become key by default, which would disable Return and Escape.
    override var canBecomeKey: Bool { true }
}
