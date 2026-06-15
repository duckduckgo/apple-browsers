//
//  YouTubeAdBlockBreakageReport.swift
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import MetricBuilder

struct YouTubeAdBlockBreakageReportView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onSend: () -> Void
    let onCancel: () -> Void

    init(onSend: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {}) {
        self.onSend = onSend
        self.onCancel = onCancel
    }

    private var contentPadding: EdgeInsets {
        horizontalSizeClass == .compact ? Constants.sheetViewPadding : Constants.popoverViewPadding
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .padding(contentPadding)
            closeButton
                .padding(16)
        }
        .background(Color(designSystemColor: .backgroundTertiary))
    }

    private var content: some View {
        VStack(spacing: Constants.mainSectionSpacing) {
            header
            buttons
        }
    }

    private var closeButton: some View {
        Button {
            onCancel()
        } label: {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
        }
        .buttonStyle(CloseButtonStyle())
        .accessibilityLabel(UserText.keyCommandClose)
    }

    private var header: some View {
        VStack(spacing: SheetMetrics.contentSpacing) {
            Image(uiImage: DesignSystemImages.Color.Size128.youTubeAdBlockWarning)
                .resizable()
                .frame(width: Constants.headerIconWidth, height: Constants.headerIconHeight)

            VStack(spacing: SheetMetrics.headerSpacing) {
                Text(UserText.youTubeAdBlockingBreakageReportTitle)
                    .daxTitle3()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(UserText.youTubeAdBlockingBreakageReportMessage)
                    .daxSubheadRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Constants.headerSectionPadding)
    }

    private var buttons: some View {
        VStack(spacing: ButtonStackMetrics.interButtonSpacing) {
            Button {
                onSend()
            } label: {
                Text(UserText.youTubeAdBlockingBreakageReportSend)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                onCancel()
            } label: {
                Text(UserText.actionCancel)
            }
            .buttonStyle(GhostButtonStyle())
        }
    }
}

private extension YouTubeAdBlockBreakageReportView {
    enum Constants {
        static let sheetViewPadding: EdgeInsets = .init(top: 24, leading: 24, bottom: 0, trailing: 24)
        static let popoverViewPadding: EdgeInsets = .init(top: 24, leading: 24, bottom: 24, trailing: 24)
        static let mainSectionSpacing: CGFloat = 16
        static let headerSectionPadding: EdgeInsets = .init(top: 24, leading: 0, bottom: 16, trailing: 0)
        static let headerIconWidth: CGFloat = 128
        static let headerIconHeight: CGFloat = 96
    }
}

#if DEBUG
#Preview {
    YouTubeAdBlockBreakageReportView()
}
#endif
