//
//  DuckPlayerEntryPillViewModel.swift
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
import UIKit

@MainActor
final class DuckPlayerEntryPillViewModel: ObservableObject {
    var onOpen: () -> Void

    @Published var isVisible: Bool = false
    /// YouTube thumbnail, only used by the floating entry pill. The legacy pill ignores it.
    @Published var thumbnailURL: URL?
    /// Downloaded thumbnail. Floating pill waits for this so it slides in as one unit.
    @Published var thumbnailImage: UIImage?
    private(set) var shouldAnimate: Bool = true

    private let videoID: String?
    private let oEmbedService: YoutubeOembedService

    init(videoID: String? = nil,
         oEmbedService: YoutubeOembedService = DefaultYoutubeOembedService(),
         onOpen: @escaping () -> Void) {
        self.videoID = videoID
        self.oEmbedService = oEmbedService
        self.onOpen = onOpen
        if let videoID {
            Task { await updateThumbnail(for: videoID) }
        }
    }

    @MainActor
    private func updateThumbnail(for videoID: String) async {
        guard let response = await oEmbedService.fetchMetadata(for: videoID),
              let url = URL(string: response.thumbnailUrl) else { return }
        thumbnailURL = url
        thumbnailImage = await DuckPlayerThumbnailLoader.loadImage(from: url)
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
}
