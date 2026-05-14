//
//  PreferencesVideoSheet.swift
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

import AppKit
import AVFoundation
import AVKit
import Common
import os.log
import SwiftUI

extension Preferences {

    struct PreferencesVideoSheet: View {

        let videoURL: URL
        /// Video size used to calculate aspect ratio for the player view.
        let videoSize: CGSize

        @Binding var isPresented: Bool
        @StateObject private var coordinator = VideoPlayerCoordinator()

        var body: some View {
            VStack(spacing: 16) {
                VideoPlayerView(player: coordinator.queuePlayer)
                    .aspectRatio(videoSize.width / videoSize.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(minWidth: Preferences.Const.minContentWidth, maxWidth: Preferences.Const.paneContentWidth)

                HStack {
                    Spacer()
                    Button(UserText.doneDialog) {
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(maxWidth: Preferences.Const.paneContentWidth)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                coordinator.loadVideoAsset(url: videoURL)
            }
            .onDisappear {
                coordinator.stop()
            }
        }
    }
}

// MARK: - Video Coordinator

@MainActor
final class VideoPlayerCoordinator: ObservableObject {

    private(set) var queuePlayer = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    func loadVideoAsset(url: URL) {
        stop()

        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.play()
    }

    func stop() {
        looper?.disableLooping()
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        looper = nil
    }
}

// MARK: - Video Player Video

/// Minimal video player implementation prevents constraint ambiguities due to compressed AVKit chrome in small SwiftUI modal.
private struct VideoPlayerView: NSViewRepresentable {

    let player: AVQueuePlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
