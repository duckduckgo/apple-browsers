//
//  WinBackOfferLaunchView.swift
//  DuckDuckGo
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
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import MetricBuilder

/// View for the Win-back offer launch prompt.
struct WinBackOfferLaunchView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    let closeAction: () -> Void
    let ctaAction: () -> Void

    var body: some View {
        let horizontalPadding = Metrics.Container.horizontalPadding.build(v: verticalSizeClass, h: horizontalSizeClass)
        
        VStack(spacing: Metrics.Container.itemsVerticalSpacing) {
            Header(action: closeAction)
                .padding(.top, Metrics.Header.verticalPadding)
                .padding(.horizontal, Metrics.Header.horizontalPadding)
            Content()
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, Metrics.Content.bottomPadding)

            Footer(ctaAction: ctaAction, dismissAction: closeAction)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, Metrics.Footer.verticalPadding)
        }
        .background(Color(designSystemColor: .surface))
    }
}

// MARK: - Inner Views

private extension WinBackOfferLaunchView {

    struct Header: View {
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        let action: () -> Void

        var body: some View {
            HStack {
                Spacer()
                Button {
                    action()
                } label: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.Header.closeButtonSize, height: Metrics.Header.closeButtonSize)
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }

    struct Content: View {
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        
        var body: some View {
            VStack(spacing: Metrics.Content.itemsVerticalSpacing) {
                let imageSize = Metrics.Content.imageSize.build(v: verticalSizeClass, h: horizontalSizeClass)

                Image(.sheetIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageSize.width, height: imageSize.height)

                VStack(spacing: Metrics.Content.textVerticalSpacing) {
                    Text(UserText.winBackCampaignModalTitle)
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(UserText.winBackCampaignModalSubtitle)
                        .daxSubheadRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .multilineTextAlignment(.center)
                }

                Text(UserText.winBackCampaignModalMessage)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    struct Footer: View {
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        
        let ctaAction: () -> Void
        let dismissAction: () -> Void

        var body: some View {
            VStack(spacing: Metrics.Footer.itemsVerticalSpacing.build(v: verticalSizeClass, h: horizontalSizeClass)) {
                Button(UserText.winBackCampaignModalCTA, action: ctaAction)
                    .buttonStyle(PrimaryButtonStyle(compact: Metrics.Footer.buttonsCompact.build(v: verticalSizeClass, h: horizontalSizeClass)))

                Button(UserText.winBackCampaignModalDismiss, action: dismissAction)
                    .buttonStyle(GhostButtonStyle(compact: Metrics.Footer.buttonsCompact.build(v: verticalSizeClass, h: horizontalSizeClass)))
            }
            .frame(maxWidth: Metrics.Footer.buttonMaxWidth.build(v: verticalSizeClass, h: horizontalSizeClass))
        }
    }
}

// MARK: - Metrics

private enum Metrics {

    enum Container {
        static let itemsVerticalSpacing: CGFloat = 0
        static let horizontalPadding = MetricBuilder<CGFloat>(iPhone: 24, iPad: 92).iPhone(landscape: 10)
    }

    enum Header {
        static let closeButtonSize: CGFloat = 24
        static let verticalPadding: CGFloat = 16
        static let horizontalPadding: CGFloat = 14
    }

    enum Content {
        static let itemsVerticalSpacing: CGFloat = 24
        static let textVerticalSpacing: CGFloat = 4
        static let imageSize = MetricBuilder<CGSize>(default: CGSize(width: 128, height: 96)).iPhone(landscape: .init(width: 96, height: 72))
        static let bottomPadding: CGFloat = 20
    }

    enum Footer {
        static let verticalPadding: CGFloat = 24
        static let itemsVerticalSpacing = MetricBuilder<CGFloat>(default: 8).iPhone(landscape: 4)
        static let buttonsCompact = MetricBuilder<Bool>(default: false).landscape(true)
        static let buttonMaxWidth = MetricBuilder<CGFloat?>(default: nil).landscape(295)
    }
}

#Preview {
    WinBackOfferLaunchView(closeAction: {}, ctaAction: {})
}
