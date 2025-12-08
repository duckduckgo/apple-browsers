//
//  FireConfirmationViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Foundation
import Combine

class FireConfirmationViewModel: ObservableObject {
    
    @Published var clearTabs: Bool = true
    @Published var clearData: Bool = true
    @Published var clearAIChats: Bool = false
    
    let showAIChatsOption: Bool = true
    
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    init(onConfirm: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    func confirm() {
        onConfirm()
    }
    
    func cancel() {
        onCancel()
    }
    
    func clearTabsSubtitle() -> String {
        let tabsCount = 1 // TODO: - Fetch actual count
        return UserText.fireConfirmationTabsSubtitle(withCount: tabsCount)
    }
    
    func clearDataSubtitle() -> String {
        let sitesCount = 1 // TODO: - Fetch actual count
        return UserText.fireConfirmationDataSubtitle(withCount: sitesCount)
    }
}
