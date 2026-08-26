//
//  RequestDirectoryReadPermissionView.swift
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

import BrowserServicesKit
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import SwiftUIExtensions

/// Asks the user to grant access to a browser data directory before importing from it.
struct RequestDirectoryReadPermissionView: View {

    enum Mode {
        case initialRequest
        case retryAfterCancel
        case retryAfterError
    }

    let source: DataImport.Source
    var mode: Mode = .initialRequest

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.iconSpacing) {
            iconView

            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                titleView
                instructionsView
                FilePickerExampleView()
                    .padding(.bottom, Metrics.filePickerExampleBottomPadding)
            }
        }
        .padding(.leading, Metrics.leadingPadding)
        .padding(.trailing, Metrics.trailingPadding)
        .padding(.vertical, Metrics.verticalPadding)
    }

    private var iconView: some View {
        Image(nsImage: mode.icon)
            .renderingMode(mode.iconTintColor == nil ? .original : .template)
            .resizable()
            .foregroundColor(mode.iconTintColor)
            .frame(width: Metrics.iconSize, height: Metrics.iconSize)
            .offset(y: Metrics.iconTopOffset)
    }

    private var titleView: some View {
        Text(mode.title(for: source))
            .font(.title2.weight(.semibold))
            .foregroundColor(Color(designSystemColor: .textPrimary))
    }

    @ViewBuilder
    private var instructionsView: some View {
        switch mode {
        case .initialRequest, .retryAfterCancel:
            instructionsText(markdownAttributedText(UserText.importBrowserDataRequestAccessDescription(for: source)))
        case .retryAfterError:
            errorInstructionStepsView
        }
    }

    private var errorInstructionStepsView: some View {
        VStack(alignment: .leading, spacing: Metrics.instructionStepSpacing) {
            ForEach(Array(errorInstructionSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Metrics.instructionNumberSpacing) {
                    instructionsText(AttributedString("\(index + 1)."))
                    instructionsText(markdownAttributedText(step))
                }
            }
        }
        .padding(.bottom, Metrics.instructionStepsBottomPadding)
    }

    private var errorInstructionSteps: [String] {
        [
            UserText.importBrowserDataRequestAccessErrorStepSelectData(for: source),
            UserText.importBrowserDataRequestAccessErrorStepDoNotNavigate,
            UserText.importBrowserDataRequestAccessErrorStepGrantAccess
        ]
    }

    private func instructionsText(_ text: AttributedString) -> some View {
        Text(text)
            .font(.body)
            .foregroundColor(Color(designSystemColor: .textPrimary))
    }

    private func markdownAttributedText(_ text: String) -> AttributedString {
        let output = try? AttributedString(markdown: text)

        return output ?? AttributedString(text)
    }
}

// MARK: - Mode Presentation

private extension RequestDirectoryReadPermissionView.Mode {

    var icon: DesignSystemImage {
        switch self {
        case .initialRequest:
            return DesignSystemImages.Glyphs.Size16.infoSolid
        case .retryAfterCancel:
            return DesignSystemImages.Glyphs.Size16.exclamationRecolorableInvert
        case .retryAfterError:
            return DesignSystemImages.Glyphs.Size16.exclamationRecolorable
        }
    }

    var iconTintColor: Color? {
        switch self {
        case .initialRequest:
            return RebrandingColor.Pondwater.pondwater50
        case .retryAfterCancel, .retryAfterError:
            return nil
        }
    }

    func title(for source: DataImport.Source) -> String {
        switch self {
        case .initialRequest:
            return UserText.importBrowserDataRequestAccessTitle(for: source)
        case .retryAfterCancel:
            return UserText.importBrowserDataRequestAccessDeniedTitle(for: source)
        case .retryAfterError:
            return UserText.importBrowserDataRequestAccessErrorTitle(for: source)
        }
    }
}

// MARK: - File Picker Mock View

private struct FilePickerExampleView: View {

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.containerCornerRadius)
            .fill(Color(designSystemColor: .containerFillTertiary))
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.containerHeight)
            .overlay(alignment: .topLeading) {
                panelView
            }
            .overlay(alignment: .bottomTrailing) {
                Image(.chromiumImportCursor)
                    .offset(x: Metrics.cursorOffset.width, y: Metrics.cursorOffset.height)
            }
    }

    private var panelView: some View {
        RoundedRectangle(cornerRadius: Metrics.panelCornerRadius)
            .fill(Color(designSystemColor: .surfacePrimary))
            .frame(height: Metrics.panelHeight)
            .shadow(color: Color(designSystemColor: .shadowPrimary),
                    radius: Metrics.panelShadowRadius,
                    y: Metrics.panelShadowOffset)
            .overlay(alignment: .bottomTrailing) {
                actionButtonsView
            }
            .padding(.horizontal, Metrics.panelHorizontalInset)
            .padding(.top, Metrics.panelTopInset)
    }

    private var actionButtonsView: some View {
        HStack(spacing: Metrics.buttonSpacing) {
            RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius)
                .fill(Color(designSystemColor: .containerFillTertiary))
                .frame(width: Metrics.placeholderButtonWidth, height: Metrics.buttonHeight)

            Text(UserText.importBrowserDataAccessPanelPrompt)
                .font(.system(size: Metrics.buttonFontSize, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .accentAltTextPrimary))
                .padding(.horizontal, Metrics.grantAccessButtonPaddingHorizontal)
                .frame(height: Metrics.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius)
                        .fill(Color(designSystemColor: .accentAltPrimary))
                )
        }
        .padding(.trailing, Metrics.buttonsTrailingInset)
        .padding(.bottom, Metrics.buttonsBottomInset)
    }
}

// MARK: - Metrics

private extension RequestDirectoryReadPermissionView {
    enum Metrics {
        static let leadingPadding: CGFloat = 21
        static let trailingPadding: CGFloat = 48
        static let verticalPadding: CGFloat = 24

        static let iconSize: CGFloat = 16
        static let iconSpacing: CGFloat = 17
        static let iconTopOffset: CGFloat = 4

        static let contentSpacing: CGFloat = 16

        static let instructionStepSpacing: CGFloat = 4
        static let instructionNumberSpacing: CGFloat = 6
        static let instructionStepsBottomPadding: CGFloat = 6

        static let filePickerExampleBottomPadding: CGFloat = 10
    }
}

private extension FilePickerExampleView {
    enum Metrics {
        static let containerHeight: CGFloat = 70
        static let containerCornerRadius: CGFloat = 12

        static let panelHeight: CGFloat = 56
        static let panelCornerRadius: CGFloat = 8
        static let panelHorizontalInset: CGFloat = 16
        static let panelTopInset: CGFloat = 0
        static let panelShadowRadius: CGFloat = 6
        static let panelShadowOffset: CGFloat = 2

        static let buttonHeight: CGFloat = 24
        static let buttonSpacing: CGFloat = 7
        static let buttonCornerRadius: CGFloat = 5
        static let buttonFontSize: CGFloat = 10
        static let grantAccessButtonPaddingHorizontal: CGFloat = 6
        static let placeholderButtonWidth: CGFloat = 60
        static let buttonsTrailingInset: CGFloat = 12
        static let buttonsBottomInset: CGFloat = 12

        static let cursorOffset = CGSize(width: 2, height: -5)
    }
}

#Preview {
    RequestDirectoryReadPermissionView(source: .chrome)
        .frame(width: 420)
}

#Preview("Retry After Cancel") {
    RequestDirectoryReadPermissionView(source: .chrome, mode: .retryAfterCancel)
        .frame(width: 420)
}

#Preview("Retry After Error") {
    RequestDirectoryReadPermissionView(source: .chrome, mode: .retryAfterError)
        .frame(width: 420)
}
