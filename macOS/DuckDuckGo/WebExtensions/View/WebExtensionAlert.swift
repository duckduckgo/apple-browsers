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

/// Asks the user to confirm an extension action. Confirm is the default button; Cancel responds to Escape.
struct WebExtensionAlert: View {

    struct Configuration {
        let icon: NSImage?
        let title: String
        let message: String?
        let details: [String]
        let checkbox: String?
        let checkboxToolTip: String?
        let confirmTitle: String
        let cancelTitle: String

        init(icon: NSImage?, title: String, message: String? = nil, details: [String] = [], checkbox: String? = nil, checkboxToolTip: String? = nil, confirmTitle: String, cancelTitle: String) {
            self.icon = icon
            self.title = title
            self.message = message
            self.details = details
            self.checkbox = checkbox
            self.checkboxToolTip = checkboxToolTip
            self.confirmTitle = confirmTitle
            self.cancelTitle = cancelTitle
        }
    }

    enum Response {
        case cancelled
        case confirmed(isChecked: Bool)
    }

    private enum Constants {
        static let width: CGFloat = 406
        static let maxHeight: CGFloat = 340
        static let cornerRadius: CGFloat = 24
        static let padding: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let contentSpacing: CGFloat = 12
        static let contentHorizontalPadding: CGFloat = 12
        static let contentBottomPadding: CGFloat = 16
        static let iconSize: CGFloat = 48
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
            if let icon = configuration.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .padding([.top, .leading], Constants.iconInset - Constants.padding)
                    .padding(.bottom, Constants.iconTitleSpacing - Constants.sectionSpacing)
            }

            content

            if let checkbox = configuration.checkbox {
                Toggle(checkbox, isOn: $isChecked)
                    .toggleStyle(.checkbox)
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                    .help(configuration.checkboxToolTip ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            buttons
        }
        .padding(Constants.padding)
        .frame(width: Constants.width)
        .frame(maxHeight: Constants.maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: Constants.cornerRadius)
            .fill(Color(designSystemColor: .surfacePrimary, palette: palette)))
    }

    /// Presents the alert as a sheet of `window`, and closes it once the user responds.
    @MainActor
    func show(in window: NSWindow) {
        let sheet = WebExtensionAlertWindow()
        var alert = self
        alert.onResponse = { [weak window, weak sheet] response in
            if let window, let sheet {
                window.endSheet(sheet)
            }
            onResponse(response)
        }
        let hostingView = NSHostingView(rootView: alert)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = Constants.cornerRadius
        hostingView.layer?.masksToBounds = true
        sheet.contentView = hostingView
        window.beginSheet(sheet)
        // The shadow is computed before SwiftUI draws, which leaves it rectangular.
        DispatchQueue.main.async { [weak sheet] in
            sheet?.invalidateShadow()
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
                // A ScrollView has no height of its own here: a hidden copy of the list sizes it, and it's
                // the only flexible part, so it shrinks when the alert reaches its maximum height.
                detailsList
                    .hidden()
                    .frame(minHeight: 0, alignment: .top)
                    .overlay(ScrollView(.vertical) { detailsList })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Constants.contentHorizontalPadding - Constants.titleLeadingOffset)
        .padding(.trailing, Constants.contentHorizontalPadding)
        .padding(.bottom, Constants.contentBottomPadding)
    }

    private func messageText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
            .multilineTextAlignment(.leading)
            .fixMultilineScrollableText()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(configuration.details.enumerated()), id: \.offset) { _, detail in
                // Wrapped lines hang under the text, not under the bullet.
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
            Button {
                respond(.cancelled)
            } label: {
                Text(configuration.cancelTitle)
                    .frame(maxWidth: .infinity)
                    .frame(height: Constants.buttonHeight)
            }
            .buttonStyle(DismissActionButtonStyle(topPadding: 0, bottomPadding: 0, pillShape: true, stateColors: .themedDismissButton))
            .keyboardShortcut(.cancelAction)

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
