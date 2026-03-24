//
//  AddToDockDemoVideoPresenter.swift
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
import AVKit
import Common
import os.log

protocol AddToDockDemoVideoPresenting: AnyObject {
    @MainActor func presentAddToDockDemoVideo()
}

/// Presents the bundled Add to Dock demo in a single non-modal window.
final class AddToDockDemoVideoPresenter: NSObject, AddToDockDemoVideoPresenting, NSWindowDelegate {

    private static let videoResourceName = "macOS_Add_To_Dock"
    private static let referenceVideoSize = CGSize(width: 898, height: 680)
    private static let defaultPresentationWidth: CGFloat = 720

    private var window: NSWindow?
    private var player: AVPlayer?
    private var endPlaybackObserver: NSObjectProtocol?

    override init() {
        super.init()
    }

    @MainActor
    func presentAddToDockDemoVideo() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            player?.seek(to: .zero)
            player?.play()
            return
        }

        guard let url = Bundle.main.url(forResource: Self.videoResourceName, withExtension: "mp4") else {
            Logger.general.error("Add to Dock demo video missing from bundle (expected \(Self.videoResourceName).mp4)")
            return
        }

        let player = AVPlayer(url: url)
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.autoresizingMask = [.width, .height]

        let contentHeight = Self.defaultPresentationWidth * (Self.referenceVideoSize.height / Self.referenceVideoSize.width)
        let contentSize = NSSize(width: Self.defaultPresentationWidth, height: contentHeight)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = UserText.addToDockDemoVideoWindowTitle
        window.contentView = playerView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setContentSize(contentSize)
        window.center()

        if let item = player.currentItem {
            endPlaybackObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        self.window = window
        self.player = player

        window.makeKeyAndOrderFront(nil)
        player.play()
    }

    func windowWillClose(_ notification: Notification) {
        player?.pause()
    }
}
