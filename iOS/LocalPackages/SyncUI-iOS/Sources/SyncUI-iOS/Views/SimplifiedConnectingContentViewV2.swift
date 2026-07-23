//
//  SimplifiedConnectingContentViewV2.swift
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

struct SimplifiedConnectingContentViewV2: View {

    let isRecovery: Bool

    var body: some View {
        VStack(spacing: 24) {
            // TODO: The design uses an animated "Lock-Feature" pictogram (a Lottie/motion node).
            // This static Sync-Lock-128 asset is an interim stand-in; swap in the canonical
            // pictogram (or the lock Lottie) when available.
            Image("Sync-Lock-128", bundle: .module)
                .padding(.top, 40)

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
    }

    private var title: String {
        isRecovery ? UserText.simplifiedRecoveringDataV2Title : UserText.simplifiedConnectingV2Title
    }
}

#if DEBUG
#Preview("Connecting") {
    SimplifiedConnectingContentViewV2(isRecovery: false)
}

#Preview("Connecting – Dark") {
    SimplifiedConnectingContentViewV2(isRecovery: false)
        .preferredColorScheme(.dark)
}

#Preview("Recovering") {
    SimplifiedConnectingContentViewV2(isRecovery: true)
}
#endif
