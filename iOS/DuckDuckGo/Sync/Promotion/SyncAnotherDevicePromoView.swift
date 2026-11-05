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
    }

    let syncBookmarksAction: () -> Void
    let getDesktopAppAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image("RemoteMessageNewForMacAndWindows")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)

                    Text(UserText.syncPromoBookmarksAnotherDeviceTitle)
                        .daxHeadline()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.trailing, 24)
                }
                .padding(.leading, 4)
                .padding(.trailing, 32)

                HStack(spacing: 8) {
                    Button(action: getDesktopAppAction) {
                        buttonLabel(UserText.syncPromoBookmarksAnotherDeviceGetDesktopAppAction)
                    }
                    .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: true))

                    Button(action: syncBookmarksAction) {
                        buttonLabel(UserText.syncPromoBookmarksAnotherDeviceSyncAction)
                    }
                    .buttonStyle(BrandButtonStyle(compact: true, fullWidth: true))
                }
                .padding(8)
            }
            .padding(16)

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

    private func buttonLabel(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

#if DEBUG
struct SyncAnotherDevicePromoView_Previews: PreviewProvider {

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots(configurations: [
        .init(name: "Default", state: ())
    ]) { _ in
        SyncAnotherDevicePromoView(syncBookmarksAction: {}, getDesktopAppAction: {}, dismissAction: {})
            .background(Color(designSystemColor: .background))
    }
}
#endif
