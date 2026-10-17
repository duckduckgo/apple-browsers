//
//  SimplifiedConnectingContentView.swift
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
import Lottie

struct SimplifiedConnectingContentView: View {

    let isRecovery: Bool
    let isFinishing: Bool
    let isWaitingForOtherDevice: Bool
    let onAnimationFinished: () -> Void

    init(isRecovery: Bool, isFinishing: Bool, isWaitingForOtherDevice: Bool = false, onAnimationFinished: @escaping () -> Void) {
        self.isRecovery = isRecovery
        self.isFinishing = isFinishing
        self.isWaitingForOtherDevice = isWaitingForOtherDevice
        self.onAnimationFinished = onAnimationFinished
    }

    var body: some View {
        VStack(spacing: 24) {
            if isWaitingForOtherDevice {
                Image(rebrandable: "Desktop-Mobile-Sync-Feature-128", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .padding(.top, 40)
            } else {
                LottieView {
                    try await DotLottieFile.named("SyncLock", bundle: .module)
                }
                .playbackMode(isFinishing
                    ? .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
                    : .paused(at: .progress(0)))
                .animationDidFinish { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        onAnimationFinished()
                    }
                }
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)
                .padding(.top, 40)
            }

            Text(title)
                .daxTitle1()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(Color(designSystemColor: .textPrimary))

            HStack(spacing: 10) {
                ProgressView()
                    .tint(Color(designSystemColor: .textSecondary))
                Text(UserText.simplifiedConnectingStatus)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
    }

    private var title: String {
        if isWaitingForOtherDevice {
            return UserText.simplifiedCheckOtherDeviceTitle
        }
        return isRecovery ? UserText.simplifiedRecoveringDataTitle : UserText.simplifiedConnectingTitle
    }
}

#if DEBUG
#Preview("Connecting") {
    SimplifiedConnectingContentView(isRecovery: false, isFinishing: false, onAnimationFinished: {})
}

#Preview("Connecting – Dark") {
    SimplifiedConnectingContentView(isRecovery: false, isFinishing: false, onAnimationFinished: {})
        .preferredColorScheme(.dark)
}

#Preview("Recovering") {
    SimplifiedConnectingContentView(isRecovery: true, isFinishing: false, onAnimationFinished: {})
}

#Preview("Check Other Device") {
    SimplifiedConnectingContentView(isRecovery: false, isFinishing: false, isWaitingForOtherDevice: true, onAnimationFinished: {})
}
#endif
