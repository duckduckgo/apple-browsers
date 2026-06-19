//
//  NewTabPageViewModel.swift
//  DuckDuckGo
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

import Foundation
import Core
import BrowserServicesKit
import Combine
import DeferredReadingCore

@MainActor
final class NewTabPageViewModel: ObservableObject {

    @Published var canEditFavorites = true
    @Published private(set) var isOnboarding: Bool
    @Published var escapeHatch: EscapeHatchModel?
    @Published var sectionTitle: String?
    @Published var isLogoHidden: Bool = false
    @Published private(set) var deferredReadingUnreadCount: Int = 0
    @Published private(set) var isDeferredReadingEnabled: Bool = false

    /// Hides the favorites grid (without removing it) so the UTI defocus handoff can keep the embedded
    /// favorites visible during the collapse and reveal these — aligned — only at completion.
    @Published var isFavoritesHidden: Bool = false
    private(set) var fireTab: Bool

    private(set) var isDragging: Bool = false

    private let pixelFiring: PixelFiring.Type
    private var cancellables = Set<AnyCancellable>()

    init(fireTab: Bool,
         deferredReadingController: DeferredReadingController? = nil,
         pixelFiring: PixelFiring.Type = Pixel.self) {
        self.fireTab = fireTab
        self.pixelFiring = pixelFiring

        isOnboarding = false

        if let deferredReadingController {
            isDeferredReadingEnabled = deferredReadingController.isEnabled
            deferredReadingUnreadCount = deferredReadingController.isEnabled ? deferredReadingController.unreadCount : 0
            deferredReadingController.$unreadCount
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak deferredReadingController] count in
                    guard let self, let deferredReadingController else { return }
                    self.isDeferredReadingEnabled = deferredReadingController.isEnabled
                    self.deferredReadingUnreadCount = deferredReadingController.isEnabled ? count : 0
                }
                .store(in: &cancellables)
        }
    }

    func startOnboarding() {
        isOnboarding = true
    }

    func finishOnboarding() {
        isOnboarding = false
    }

    func beginDragging() {
        isDragging = true
    }

    func endDragging() {
        isDragging = false
    }
}
