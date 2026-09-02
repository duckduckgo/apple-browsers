//
//  PreparingToSyncViewV2.swift
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
import Lottie
import SwiftUI

struct PreparingToSyncViewV2: View {

    enum State {
        case connecting
        case waitingForOtherDevice
    }

    let state: State

    var body: some View {
        VStack(spacing: 20) {
            artwork

            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(UserText.preparingToSyncDialogActionV2)
                .font(.body)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(width: 420)
        .background(Color(designSystemColor: .surfaceSecondary))
        .fixedSize()
    }

    @ViewBuilder
    private var artwork: some View {
        switch state {
        case .connecting:
            LottieView {
                try await DotLottieFile.named("SyncLock", bundle: .module)
            }
            .playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 96, height: 72)
            .accessibilityHidden(true)
        case .waitingForOtherDevice:
            Image(.desktopMobileSync128)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 72)
                .accessibilityHidden(true)
        }
    }

    private var title: String {
        switch state {
        case .connecting:
            UserText.preparingToSyncDialogTitleV2
        case .waitingForOtherDevice:
            UserText.preparingToSyncCheckOtherDeviceTitleV2
        }
    }

}
