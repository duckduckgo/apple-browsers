//
//  AIChatContextualModePixelHandler.swift
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

import Core
import Foundation

/// Protocol for firing contextual mode pixels, enabling dependency injection and testing.
protocol AIChatContextualModePixelFiring {
    // MARK: - Sheet Lifecycle
    func fireSheetOpened()
    func fireSheetDismissed()
    func fireSessionRestored()

    // MARK: - Sheet Actions
    func fireExpandButtonTapped()
    func fireNewChatButtonTapped()
    func fireQuickActionSummarizeSelected()

    // MARK: - Page Context Attachment
    func firePageContextPlaceholderShown()
    func firePageContextPlaceholderTapped()
    func firePageContextAutoAttached()
    func firePageContextUpdatedOnNavigation(url: String)
    func firePageContextManuallyAttachedNative()
    func firePageContextManuallyAttachedFrontend()

    // MARK: - Page Context Removal
    func firePageContextRemovedNative()
    func firePageContextRemovedFrontend()

    // MARK: - Prompt Submission
    func firePromptSubmittedWithContext()
    func firePromptSubmittedWithoutContext()

    // MARK: - Manual Attach State
    func beginManualAttach()
    func endManualAttach()
    var isManualAttachInProgress: Bool { get }

    // MARK: - URL Priming
    func primeNavigationURL(_ url: String)

    // MARK: - Reset
    func reset()
}

/// Handles all pixel firing for contextual AI chat mode.
/// Single source of truth for contextual mode analytics.
///
/// **Thread Safety**: This class is thread-safe. All mutable state access is synchronized using a serial queue.
final class AIChatContextualModePixelHandler: AIChatContextualModePixelFiring {

    // MARK: - State

    /// Serial queue for synchronizing access to mutable state
    private let stateQueue = DispatchQueue(label: "com.duckduckgo.aichat.contextual.pixelhandler", qos: .userInitiated)

    /// Tracks the last URL for which navigation pixel was fired, to prevent duplicates.
    private var _lastNavigationPixelURL: String?

    /// Tracks whether a manual attach operation is in progress.
    private var _isManualAttachInProgress = false

    // MARK: - Dependencies

    private let firePixel: (Pixel.Event) -> Void

    // MARK: - Public Properties

    var isManualAttachInProgress: Bool {
        stateQueue.sync { _isManualAttachInProgress }
    }

    // MARK: - Initialization

    init(firePixel: @escaping (Pixel.Event) -> Void = { DailyPixel.fireDailyAndCount(pixel: $0) }) {
        self.firePixel = firePixel
    }

    // MARK: - Sheet Lifecycle

    func fireSheetOpened() {
        firePixel(.aiChatContextualSheetOpened)
    }

    func fireSheetDismissed() {
        firePixel(.aiChatContextualSheetDismissed)
    }

    func fireSessionRestored() {
        firePixel(.aiChatContextualSessionRestored)
    }

    // MARK: - Sheet Actions

    func fireExpandButtonTapped() {
        firePixel(.aiChatContextualExpandButtonTapped)
    }

    func fireNewChatButtonTapped() {
        firePixel(.aiChatContextualNewChatButtonTapped)
    }

    func fireQuickActionSummarizeSelected() {
        firePixel(.aiChatContextualQuickActionSummarizeSelected)
    }

    // MARK: - Page Context Attachment

    func firePageContextPlaceholderShown() {
        firePixel(.aiChatContextualPageContextPlaceholderShown)
    }

    func firePageContextPlaceholderTapped() {
        firePixel(.aiChatContextualPageContextPlaceholderTapped)
    }

    func firePageContextAutoAttached() {
        firePixel(.aiChatContextualPageContextAutoAttached)
    }

    func firePageContextUpdatedOnNavigation(url: String) {
        stateQueue.sync {
            guard !_isManualAttachInProgress else { return }
            guard url != _lastNavigationPixelURL else { return }
            _lastNavigationPixelURL = url
            firePixel(.aiChatContextualPageContextUpdatedOnNavigation)
        }
    }

    func firePageContextManuallyAttachedNative() {
        firePixel(.aiChatContextualPageContextManuallyAttachedNative)
    }

    func firePageContextManuallyAttachedFrontend() {
        firePixel(.aiChatContextualPageContextManuallyAttachedFrontend)
    }

    // MARK: - Page Context Removal

    func firePageContextRemovedNative() {
        firePixel(.aiChatContextualPageContextRemovedNative)
    }

    func firePageContextRemovedFrontend() {
        firePixel(.aiChatContextualPageContextRemovedFrontend)
    }

    // MARK: - Prompt Submission

    func firePromptSubmittedWithContext() {
        firePixel(.aiChatContextualPromptSubmittedWithContextNative)
    }

    func firePromptSubmittedWithoutContext() {
        firePixel(.aiChatContextualPromptSubmittedWithoutContextNative)
    }

    // MARK: - Manual Attach State

    func beginManualAttach() {
        stateQueue.sync {
            _isManualAttachInProgress = true
        }
    }

    func endManualAttach() {
        stateQueue.sync {
            _isManualAttachInProgress = false
        }
    }

    // MARK: - URL Priming

    func primeNavigationURL(_ url: String) {
        stateQueue.sync {
            _lastNavigationPixelURL = url
        }
    }

    // MARK: - Reset

    /// Resets state. Call when the contextual session ends.
    func reset() {
        stateQueue.sync {
            _lastNavigationPixelURL = nil
            _isManualAttachInProgress = false
        }
    }
}
