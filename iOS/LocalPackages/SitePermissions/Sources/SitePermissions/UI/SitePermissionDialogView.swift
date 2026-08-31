//
//  SitePermissionDialogView.swift
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
import SwiftUI
import UIKit

public struct SitePermissionDialogView: View {

    private enum Constants {
        static let cardWidth: CGFloat = 300
        static let contentHorizontalPadding: CGFloat = 8
        static let iconSize: CGFloat = 24
        static let iconContainerSize: CGFloat = 48
        static let iconContainerCornerRadius: CGFloat = 12
        static let headerSpacing: CGFloat = 16
        static let bodySpacing: CGFloat = 8
        static let actionsTopPadding: CGFloat = 24
        static let buttonSpacing: CGFloat = 8
        static let cardHorizontalPadding: CGFloat = 14
    }

    private let viewModel: SitePermissionDialogViewModel
    let onAction: (SitePermissionDialogAction) -> Void

    @AccessibilityFocusState private var isTitleFocused: Bool

    public init(viewModel: SitePermissionDialogViewModel,
                onAction: @escaping (SitePermissionDialogAction) -> Void) {
        self.viewModel = viewModel
        self.onAction = onAction
    }

    public var body: some View {
        PermissionDialogCard(width: Constants.cardWidth,
                             accessibilityIdentifier: "SitePermissions.Dialog") {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Constants.headerSpacing) {
                    if let icon = viewModel.icon {
                        iconView(for: icon)
                    }
                    VStack(alignment: .leading, spacing: Constants.bodySpacing) {
                        title
                        if let body = viewModel.body {
                            Text(body)
                                .daxBodyRegular()
                                .foregroundColor(Color(designSystemColor: .textPrimary))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("SitePermissions.Dialog.Body")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Constants.contentHorizontalPadding)

                VStack(spacing: Constants.buttonSpacing) {
                    ForEach(viewModel.actions) { item in
                        Button(item.title) {
                            onAction(item.action)
                        }
                        .buttonStyle(SecondaryFillButtonStyle())
                        .accessibilityIdentifier(accessibilityIdentifier(for: item.action))
                    }
                }
                .padding(.top, Constants.actionsTopPadding)
            }
        }
    }

    private var title: some View {
        Text(viewModel.title(domain: truncatedDomain))
            .daxBodyBold()
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(viewModel.title)
            .accessibilityFocused($isTitleFocused)
            .accessibilityIdentifier("SitePermissions.Dialog.Title")
            .onAppear {
                isTitleFocused = true
            }
    }

    private var truncatedDomain: String {
        let availableWidth = Constants.cardWidth
            - 2 * Constants.cardHorizontalPadding
            - 2 * Constants.contentHorizontalPadding
        let font = UIFont.daxBodyBold()
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        func fits(_ value: String) -> Bool {
            ("“\(value)”" as NSString).size(withAttributes: attributes).width <= availableWidth
        }

        guard !fits(viewModel.domain) else { return viewModel.domain }

        let characters = Array(viewModel.domain)
        for retainedCount in stride(from: characters.count - 1, through: 1, by: -1) {
            let prefixCount = (retainedCount + 1) / 2
            let suffixCount = retainedCount / 2
            let candidate = String(characters.prefix(prefixCount)) + "…" + String(characters.suffix(suffixCount))
            if fits(candidate) {
                return candidate
            }
        }
        return "…"
    }

    private func iconView(for icon: SitePermissionDialogViewModel.Icon) -> some View {
        image(for: icon)
            .renderingMode(icon == .duckDuckGo ? .original : .template)
            .resizable()
            .scaledToFit()
            .frame(width: Constants.iconSize, height: Constants.iconSize)
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .frame(width: Constants.iconContainerSize, height: Constants.iconContainerSize)
            .background(AppRebrand.isAppRebranded()
                        ? Color(singleUseColor: .rebranding(.buttonsSecondaryDefault))
                        : Color(designSystemColor: .buttonsSecondaryFillDefault))
            .clipShape(RoundedRectangle(cornerRadius: Constants.iconContainerCornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    private func image(for icon: SitePermissionDialogViewModel.Icon) -> Image {
        switch icon {
        case .camera:
            return Image(systemName: "video")
        case .microphone:
            if #available(iOS 18.0, *) {
                return Image(systemName: "microphone")
            }
            return Image(systemName: "mic")
        case .location:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.location)
        case .duckDuckGo:
            return Image(uiImage: DesignSystemImages.Glyphs.Size24.duckDuckGoDaxColor)
        }
    }

    private func accessibilityIdentifier(for action: SitePermissionDialogAction) -> String {
        switch action {
        case .allowOnce:
            return "SitePermissions.Dialog.AllowOnce"
        case .allowWhileUsingSite:
            return "SitePermissions.Dialog.AllowWhileUsingSite"
        case .neverAllow:
            return "SitePermissions.Dialog.NeverAllow"
        }
    }
}
