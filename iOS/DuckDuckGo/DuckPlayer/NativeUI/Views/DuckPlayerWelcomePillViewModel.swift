//
//  DuckPlayerWelcomePillViewModel.swift
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
import SwiftUI

@MainActor
final class DuckPlayerWelcomePillViewModel: ObservableObject {
    var onOpen: () -> Void
    var onClose: (() -> Void)?

    @Published var isVisible: Bool = false
    private(set) var shouldAnimate: Bool = true

    init(onOpen: @escaping () -> Void, onClose: (() -> Void)? = nil) {
        self.onOpen = onOpen
        self.onClose = onClose
    }

    func updateOnOpen(_ onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        shouldAnimate = false
    }

    func openInDuckPlayer() {
        onOpen()
    }

    func show() {
        self.isVisible = true
    }

    func hide() {
        isVisible = false
    }
    
    func close() {
        onClose?()
    }
}
