//
//  AddToDockDemoVideoSheet.swift
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

    /// Sheet content width aligns with other preferences modals (e.g. About unsupported banner `maxWidth` 510, AI Chat dialog 360, VPN sheet 400). Video uses `maxContentWidth` 544 with a floor so AVKit’s transport bar can lay out (SwiftUI `VideoPlayer` was squeezed to ~180pt and broke internal constraints).
    struct AddToDockDemoVideoSheet: View {

        fileprivate static let videoResourceName = "macOS_Add_To_Dock"
        fileprivate static let referenceVideoSize = CGSize(width: 898, height: 680)
        /// Wider than typical text sheets so the demo stays readable; cap requested by product.
        fileprivate static let maxContentWidth: CGFloat = 544
        /// AVPlayerView’s control chrome needs a minimum width; below ~300–360pt, AppKit logs unsatisfiable constraints on the volume/scrubber row.
        fileprivate static let minPlayerWidth: CGFloat = 400

        @Binding var isPresented: Bool
        @StateObject private var coordinator = AddToDockDemoVideoPlayerCoordinator()

        var body: some View {
            VStack(spacing: 16) {
                if let player = coordinator.queuePlayer {
                    AddToDockAVPlayerView(player: player)
                        .aspectRatio(
                            Self.referenceVideoSize.width / Self.referenceVideoSize.height,
                            contentMode: .fit
                        )
                        .frame(minWidth: Self.minPlayerWidth, maxWidth: Self.maxContentWidth)
                } else {
                    Text(UserText.addToDockDemoVideoUnavailable)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: Self.maxContentWidth)
                        .frame(minHeight: 120)
                }

                HStack {
                    Spacer()
                    Button(UserText.doneDialog) {
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(maxWidth: Self.maxContentWidth)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                coordinator.loadBundledVideoIfNeeded(resourceName: Self.videoResourceName)
            }
            .onDisappear {
                coordinator.stop()
            }
        }
    }
}

// MARK: - Player coordinator (macOS)

/// Owns looping playback for the Add to Dock demo. API is intentionally smaller than iOS `VideoPlayerCoordinator` (no `AudioSessionManaging`, UIKit PiP, or async `AVURLAsset` load). A future shared module could extract a common core (`AVQueuePlayer` + `AVPlayerLooper`, load/play/stop) and keep platform adapters separate.
@MainActor
final class AddToDockDemoVideoPlayerCoordinator: ObservableObject {

    @Published private(set) var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    func loadBundledVideoIfNeeded(resourceName: String) {
        guard queuePlayer == nil else { return }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            Logger.general.error("Add to Dock demo video missing from bundle (expected \(resourceName).mp4)")
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        player.play()
    }

    func stop() {
        queuePlayer?.pause()
        looper = nil
        queuePlayer = nil
    }
}

// MARK: - AppKit player (avoids SwiftUI VideoPlayer layout bugs on macOS)

private struct AddToDockAVPlayerView: NSViewRepresentable {

    let player: AVQueuePlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .minimal
        view.showsFullScreenToggleButton = false
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
