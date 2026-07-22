//
//  RecoveringDataContentViewV2.swift
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

struct RecoveringDataContentViewV2: View {

    var body: some View {
        VStack(spacing: 24) {
            Image("Sync-Lock-128", bundle: .module)
                .padding(.top, 40)

            Text(UserText.simplifiedRecoveringDataV2Title)
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
}

#if DEBUG
#Preview("Recovering Data") {
    RebrandedPreview(isRebranded: true) {
        RecoveringDataContentViewV2()
    }
}

#Preview("Recovering Data – Dark") {
    RebrandedPreview(isRebranded: true) {
        RecoveringDataContentViewV2()
    }
    .preferredColorScheme(.dark)
}
#endif
