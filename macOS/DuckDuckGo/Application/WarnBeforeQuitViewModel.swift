//
//  WarnBeforeQuitViewModel.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine
import Foundation

@MainActor
final class WarnBeforeQuitViewModel: ObservableObject {

    @Published private(set) var progress: CGFloat = 0

    var onDontAskAgain: (() -> Void)?

    func updateProgress(_ newProgress: CGFloat) {
        progress = min(1.0, max(0, newProgress))
    }

    func resetProgress() {
        progress = 0
    }

    func dontAskAgainTapped() {
        onDontAskAgain?()
    }
}
