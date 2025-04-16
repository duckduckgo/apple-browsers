//
//  DuckPlayerMiniPillViewModel.swift
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
import WebKit

final class DuckPlayerMiniPillViewModel: ObservableObject {
    var onOpen: () -> Void
    var videoID: String = ""

    @Published var isVisible: Bool = false
    @Published var title: String = ""
    @Published var thumbnailURL: URL?
    @Published var authorName: String?

    private(set) var shouldAnimate: Bool = true
    private var titleUpdateTask: Task<Void, Error>?
    private var oEmbedService: YoutubeOembedService

   init(onOpen: @escaping () -> Void, videoID: String, oEmbedService: YoutubeOembedService = DefaultYoutubeOembedService()) {
    self.onOpen = onOpen
    self.videoID = videoID
    self.oEmbedService = oEmbedService
    Task { try await updateMetadata() }

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

    // Gets the video title from the Youtube API oembed endpoint
    @MainActor
    private func updateMetadata() async throws {
        if let response = await oEmbedService.fetchMetadata(for: videoID) {
            self.title = response.title
            self.authorName = response.authorName
            self.thumbnailURL = URL(string: response.thumbnailUrl)
        }

    }

}
