//
//  ManagementView.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions

enum Const {
    enum Fonts {
        static let preferencePaneTitle: Font = .title2.weight(.semibold)
        static let preferencePaneSectionHeader: Font = .title3.weight(.semibold)
        static let preferencePaneOptionTitle: Font = .title3
        static let preferencePaneCaption: Font = .subheadline
    }
}

public struct ManagementView<ViewModel>: View where ViewModel: ManagementViewModel {
    @ObservedObject public var model: ViewModel

    private var syncStatus: StatusIndicator {
        model.isSyncEnabled ? .on : .off
    }

    public init(model: ViewModel) {
        self.model = model
    }

    public var body: some View {
        PreferencePane {
            TextMenuItemHeader(UserText.sync)
                .padding(.bottom, -22)

            StatusIndicatorView(status: syncStatus, isLarge: true)

            if model.isSyncEnabled {
                SyncEnabledView<ViewModel>()
                    .environmentObject(model)
            } else if model.isSimplifiedSyncSetupV2Enabled {
                SyncSetupViewV2<ViewModel>()
                    .environmentObject(model)
            } else {
                SyncSetupView<ViewModel>()
                    .environmentObject(model)
            }
        }
    }
}

#if DEBUG
#Preview("Enabled") {
    let devices = [
        SyncDevice(kind: .current, name: "My Mac", id: "current-device"),
        SyncDevice(kind: .desktop, name: "MacBook Pro", id: "desktop-device"),
        SyncDevice(kind: .mobile, name: "iPhone", id: "mobile-device")
    ]

    return ScrollView {
        ManagementView(model: PreviewManagementViewModel(isSyncEnabled: false, devices: devices))
            .frame(width: 544)
            .padding()
    }
    .frame(height: 800)
}
#endif
