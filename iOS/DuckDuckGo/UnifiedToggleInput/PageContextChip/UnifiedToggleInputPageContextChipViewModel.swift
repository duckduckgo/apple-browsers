//
//  UnifiedToggleInputPageContextChipViewModel.swift
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

import Combine
import Foundation
import os.log

@MainActor
final class UnifiedToggleInputPageContextChipViewModel: ObservableObject {

    @Published private(set) var isVisible: Bool = false

    private let onAttach: (URL) -> Void
    private var originatingURL: URL?
    private var attachedURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        attachedURLPublisher: AnyPublisher<URL?, Never>,
        onAttach: @escaping (URL) -> Void
    ) {
        self.onAttach = onAttach
        originatingURLPublisher
            .sink { [weak self] in self?.handleOriginatingURL($0) }
            .store(in: &cancellables)
        attachedURLPublisher
            .sink { [weak self] in self?.handleAttachedURL($0) }
            .store(in: &cancellables)
    }

    func tapped() {
        guard let url = originatingURL else {
            Logger.contextualUTI.debug("PageContextChip tapped but no originating URL — ignoring")
            return
        }
        Logger.contextualUTI.info("PageContextChip tapped — attaching \(url.absoluteString, privacy: .public)")
        onAttach(url)
    }

    private func handleOriginatingURL(_ url: URL?) {
        originatingURL = url
        recomputeVisibility(reason: "originatingURL changed")
    }

    private func handleAttachedURL(_ url: URL?) {
        attachedURL = url
        recomputeVisibility(reason: "attachedURL changed")
    }

    private func recomputeVisibility(reason: String) {
        let next: Bool
        if let originating = originatingURL, originating != attachedURL {
            next = true
        } else {
            next = false
        }
        if next != isVisible {
            Logger.contextualUTI.debug("PageContextChip visibility \(self.isVisible) → \(next) — \(reason, privacy: .public)")
            isVisible = next
        }
    }
}
