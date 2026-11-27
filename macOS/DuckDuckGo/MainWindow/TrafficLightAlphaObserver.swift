//
//  TrafficLightAlphaObserver.swift
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
import AppKitExtensions
import Combine

/// Keeps a window's traffic lights visible while AppKit tries to fade them out, as it does in full screen.
@MainActor
final class TrafficLightAlphaObserver: NSObject {

    nonisolated static let buttonRevealAmountKey = "buttonRevealAmount"
    nonisolated static let buttonRevealAmountSelector = NSSelectorFromString(buttonRevealAmountKey)

    private weak var observedFrameView: NSView?
    private var alphaValueCancellables = [AnyCancellable]()
    private var isRestoringButtonRevealAmount = false

    deinit {
        observedFrameView?.removeObserver(self, forKeyPath: Self.buttonRevealAmountKey)
    }

    init(window: NSWindow) {
        super.init()

        if #available(macOS 27.0, *) {
            observeButtonRevealAmount(in: window)
        } else {
            observeAlphaValue(in: window)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        restoreButtonRevealAmount()
    }
}

// MARK: - Pre macOS 27: AppKit fades the traffic lights through `alphaValue`

private extension TrafficLightAlphaObserver {

    func observeAlphaValue(in window: NSWindow) {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        alphaValueCancellables = buttonTypes.compactMap { window.standardWindowButton($0) }.map { button in
            button
                .publisher(for: \.alphaValue)
                .sink { [weak button] alphaValue in
                    if let button, alphaValue != .activeViewAlpha {
                        button.alphaValue = .activeViewAlpha
                    }
                }
        }
    }
}

// MARK: - macOS 27: AppKit fades them through a private value on the window's frame view, and `alphaValue` only follows it

private extension TrafficLightAlphaObserver {

    func observeButtonRevealAmount(in window: NSWindow) {
        guard let frameView = window.contentView?.superview, frameView.responds(to: Self.buttonRevealAmountSelector) else {
            return
        }

        frameView.addObserver(self, forKeyPath: Self.buttonRevealAmountKey, options: [], context: nil)
        observedFrameView = frameView
    }

    func restoreButtonRevealAmount() {
        guard !isRestoringButtonRevealAmount, Thread.isMainThread else {
            return
        }

        guard let observedFrameView, let currentAlpha = observedFrameView.value(forKey: Self.buttonRevealAmountKey) as? CGFloat, currentAlpha != CGFloat.activeViewAlpha else {
            return
        }

        isRestoringButtonRevealAmount = true
        observedFrameView.setValue(CGFloat.activeViewAlpha, forKey: Self.buttonRevealAmountKey)
        isRestoringButtonRevealAmount = false
    }
}
