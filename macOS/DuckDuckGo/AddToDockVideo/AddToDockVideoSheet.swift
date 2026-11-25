//
//  AddToDockVideoSheet.swift
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
import FeatureFlags_macOS
import FoundationExtensions
import os.log
import PrivacyConfig
import SwiftUI
import DesignResourcesKitIcons
import SwiftUIExtensions

struct AddToDockVideoSheet: View {

    private enum Layout {
        static let minWidth: CGFloat = 384
        static let maxWidth: CGFloat = 424
    }

    let videoURL: URL
    /// Video size used to calculate aspect ratio for the player view.
    let videoSize: CGSize
    let primaryAction: AddToDockVideoAction.Primary
    let showsInstructions: Bool
    let onAction: (AddToDockVideoAction) -> Void
    private let featureFlagger: FeatureFlagger
    @ObservedObject private var themeManager: ThemeManager

    @Binding var isPresented: Bool
    @StateObject private var coordinator = VideoPlayerCoordinator()

    init(videoURL: URL,
         videoSize: CGSize,
         primaryAction: AddToDockVideoAction.Primary = .done,
         showsInstructions: Bool = false,
         isPresented: Binding<Bool>,
         onAction: @escaping (AddToDockVideoAction) -> Void = { _ in },
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         themeManager: ThemeManager = NSApp.delegateTyped.themeManager) {
        self.videoURL = videoURL
        self.videoSize = videoSize
        self.primaryAction = primaryAction
        self.showsInstructions = showsInstructions
        self.onAction = onAction
        self.featureFlagger = featureFlagger
        self.themeManager = themeManager
        self._isPresented = isPresented
    }

    var body: some View {
        VStack(spacing: 16) {
            VideoPlayerView(player: coordinator.queuePlayer)
                .aspectRatio(videoSize.width / videoSize.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(minWidth: Layout.minWidth, maxWidth: Layout.maxWidth)

            if showsInstructions {
                HStack(alignment: .top, spacing: 8) {
                    Image(nsImage: DesignSystemImages.Color.Size16.addToDock)
                        .accessibilityHidden(true)
                    Text(.init(UserText.addToDockInstructionsCaption))
                }
                .frame(minWidth: Layout.minWidth, maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if showsCancelButton {
                    Button(UserText.cancel) {
                        select(.cancel)
                    }
                    .buttonStyle(DismissActionButtonStyle(stateColors: .themedDismissButton))
                    .keyboardShortcut(.cancelAction)
                }
                Button(primaryButtonTitle) {
                    select(primaryAction.action)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, stateColors: .themedActionButton))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .background(Color(designSystemColor: .surfaceTertiary, palette: themeManager.designColorPalette))
        .frame(maxWidth: Layout.maxWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            coordinator.loadVideoAsset(url: videoURL)
        }
        .onDisappear {
            coordinator.stop()
        }
    }

    private var showsCancelButton: Bool {
        primaryAction == .next || featureFlagger.isFeatureOn(.appStoreAddToDockOnlyCTA)
    }

    private var primaryButtonTitle: String {
        switch primaryAction {
        case .done: return UserText.doneDialog
        case .next: return UserText.next
        }
    }

    private func select(_ action: AddToDockVideoAction) {
        onAction(action)
        isPresented = false
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
        queuePlayer.isMuted = true
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
        view.updatesNowPlayingInfoCenter = false
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
