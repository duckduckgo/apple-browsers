//
//  ScopedFireConfirmationViewModel.swift
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

import Foundation
import Core

@MainActor
final class ScopedFireConfirmationViewModel: ObservableObject {
    
    // MARK: - Public Variables
    
    let onConfirm: (FireRequest) -> Void
    let onCancel: () -> Void
    
    // MARK: - Private Variables
    
    
    // MARK: - Initializer
    
    init(onConfirm: @escaping (FireRequest) -> Void,
         onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    // MARK: - Public Functions
    
    func burnAllTabs() {
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .all)
        onConfirm(request)
    }
    
    func burnThisTab() {
    }
    
    func cancel() {
        onCancel()
    }
}
