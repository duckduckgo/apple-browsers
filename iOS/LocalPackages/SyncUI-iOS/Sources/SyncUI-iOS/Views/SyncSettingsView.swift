//
//  SyncSettingsView.swift
//  DuckDuckGo
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

import SwiftUI

public struct SyncSettingsRootView: View {
    @ObservedObject var model: SyncSettingsViewModel

    private let useSimplifiedLayoutV2: Bool

    public init(model: SyncSettingsViewModel, useSimplifiedLayoutV2: Bool) {
        self.model = model
        self.useSimplifiedLayoutV2 = useSimplifiedLayoutV2
    }

    public var body: some View {
        if useSimplifiedLayoutV2 {
            SimplifiedSyncSettingsViewV2(model: model)
        } else {
            SimplifiedSyncSettingsView(model: model)
        }
    }
}
