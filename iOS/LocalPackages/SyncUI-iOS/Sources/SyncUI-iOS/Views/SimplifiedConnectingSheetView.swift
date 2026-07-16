//
//  SimplifiedConnectingSheetView.swift
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


public struct SimplifiedConnectingSheetView: View {

    public enum Context {
        case syncingDevices
        case recoveringData
    }

    private let context: Context

    public init(context: Context = .syncingDevices) {
        self.context = context
    }

    public var body: some View {
        VStack(spacing: 24) {
            Image(rebrandable: "Sync-128")
                .padding(.top, 40)

            Text(title)
                .daxTitle3()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.horizontal, 40)

            HStack(spacing: 8) {
                ProgressView()
                    .tint(Color(designSystemColor: .textSecondary))
                Text(UserText.simplifiedConnectingStatus)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
    }

    private var title: String {
        switch context {
        case .syncingDevices:
            return UserText.simplifiedConnectingTitle
        case .recoveringData:
            return UserText.preparingToSyncTitle
        }
    }
}
