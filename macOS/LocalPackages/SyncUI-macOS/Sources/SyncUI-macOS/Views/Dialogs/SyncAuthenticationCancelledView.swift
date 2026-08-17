//
//  SyncAuthenticationCancelledView.swift
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
import SwiftUIExtensions
import DesignResourcesKit

struct SyncAuthenticationCancelledView: View {
    @EnvironmentObject var model: ManagementDialogModel

    var body: some View {
        SyncDialogV2(spacing: 20.0) {
            VStack(alignment: .center, spacing: 20) {
                Image(.lockDuckDuckGo128)
                SyncUIViewsV2.TextHeader(text: UserText.syncAuthenticationCancelledTitleV2)
                SyncUIViewsV2.TextDetailSecondary(text: UserText.syncAuthenticationCancelledSubtitleV2)
            }
        } buttons: {
            Spacer()
            Button {
                model.endFlow()
            } label: {
                Text(UserText.syncAuthenticationCancelledCloseButtonV2)
            }
        }
    }
}

#if DEBUG
#Preview("Default") {
    DesignSystemRebrand.isAppRebranded = { true }
    return SyncAuthenticationCancelledView()
        .environmentObject(ManagementDialogModel())
}
#endif
