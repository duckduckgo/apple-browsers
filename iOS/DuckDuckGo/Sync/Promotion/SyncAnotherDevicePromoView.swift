//
//  SyncAnotherDevicePromoView.swift
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

#if DEBUG
import PreviewSnapshots
#endif

struct SyncAnotherDevicePromoView: View {

    private enum Metrics {
        static let closeButtonInset: CGFloat = 12
        static let closeButtonReserve: CGFloat = 52
        static let imageSize: CGFloat = 56
        static let iconSize: CGFloat = 16
    }

    let title: String
    let syncAction: () -> Void
    let getDesktopAppAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Image("RemoteMessageNewForMacAndWindows")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.imageSize, height: Metrics.imageSize)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .daxHeadline()
                            .foregroundColor(Color(designSystemColor: .textPrimary))

                        Text(UserText.syncPromoAnotherDeviceMessage)
                            .daxSubheadRegular()
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
                .padding(.top, 8)
                .padding(.leading, 16)
                .padding(.trailing, Metrics.closeButtonReserve)

                buttons
                    .padding(.leading, 16)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
            }
            .padding(.top, 12)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.bottom, 16)

            Button(action: dismissAction) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
            }
            .buttonStyle(CloseButtonStyle())
            .padding(Metrics.closeButtonInset - CloseButtonStyle.Constant.padding)
            .accessibilityLabel(UserText.syncPromoCloseAccessibilityLabel)
        }
        .background(
            RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius)
                .foregroundColor(Color(designSystemColor: .surfaceSecondary))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var buttons: some View {
        if #available(iOS 16, *) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    getDesktopAppButton(widestLabel: true)
                    connectButton(widestLabel: true)
                }
                VStack(spacing: 8) {
                    connectButton(widestLabel: false)
                    getDesktopAppButton(widestLabel: false)
                }
            }
        } else {
            VStack(spacing: 8) {
                connectButton(widestLabel: false)
                getDesktopAppButton(widestLabel: false)
            }
        }
    }

    private func getDesktopAppButton(widestLabel: Bool) -> some View {
        Button(action: getDesktopAppAction) {
            equalWidthLabel(getDesktopAppLabel, widestLabel: widestLabel)
        }
        .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: true))
    }

    private func connectButton(widestLabel: Bool) -> some View {
        Button(action: syncAction) {
            equalWidthLabel(connectLabel, widestLabel: widestLabel)
        }
        .buttonStyle(PrimaryButtonStyle(compact: true, fullWidth: true))
    }

    private func equalWidthLabel(_ label: some View, widestLabel: Bool) -> some View {
        ZStack {
            if widestLabel {
                getDesktopAppLabel.hidden()
                connectLabel.hidden()
            }
            label
        }
    }

    private var getDesktopAppLabel: some View {
        Text(UserText.syncPromoAnotherDeviceGetDesktopAppAction)
            .lineLimit(1)
    }

    private var connectLabel: some View {
        HStack(spacing: 8) {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.qrScan)
                .resizable()
                .renderingMode(.template)
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                .accessibilityHidden(true)
            Text(UserText.syncPromoAnotherDeviceConnectAction)
                .lineLimit(1)
        }
    }
}

#if DEBUG
struct SyncAnotherDevicePromoView_Previews: PreviewProvider {

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots(configurations: [
        .init(name: "Bookmarks", state: UserText.syncPromoBookmarksAnotherDeviceTitle),
        .init(name: "Passwords", state: UserText.syncPromoPasswordsAnotherDeviceTitle)
    ]) { title in
        SyncAnotherDevicePromoView(title: title, syncAction: {}, getDesktopAppAction: {}, dismissAction: {})
            .background(Color(designSystemColor: .background))
    }
}
#endif
