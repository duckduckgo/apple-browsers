//
//  DeviceActivityView.swift
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

import DesignResourcesKit
import DuckUI
import SwiftUI

struct DeviceActivityView: View {

    var body: some View {
        List {
            Section {
                Text(UserText.deviceActivityIntro)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(UserText.deviceActivityEmpty)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }
            .listRowBackground(Color(designSystemColor: .surfaceTertiary))
        }
        .navigationTitle(UserText.deviceActivityTitle)
        .navigationBarTitleDisplayMode(.inline)
        .applyListStyle()
    }
}
