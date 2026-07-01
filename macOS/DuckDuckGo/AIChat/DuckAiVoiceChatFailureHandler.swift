//
//  DuckAiVoiceChatFailureHandler.swift
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

import AVFoundation
import Foundation
import PixelKit
import WebKit

/// Which Duck.ai mic-using flow triggered the OS-disabled remediation prompt. Selects the
/// copy shown in `SystemDisabledPermissionInfoView`; the underlying detection and surface are
/// identical for both.
enum DuckAiMicPermissionSource {
    case voiceChat
    case dictation
}

protocol DuckAiVoiceChatFailureHandling: AnyObject {
    /// Called when the Duck.ai FE posts `voiceChatStartFailed` after `getUserMedia` rejects.
    /// `reason` is the `error.name` from the FE (e.g. `"NotAllowedError"`).
    @MainActor func handleVoiceChatStartFailed(reason: String, sourceWebView: WKWebView?)

    /// Called when the Duck.ai FE posts `dictationStartFailed` after `getUserMedia` rejects.
    /// Same handling as voice chat; only the surfaced remediation copy differs.
    @MainActor func handleDictationStartFailed(reason: String, sourceWebView: WKWebView?)
}

/// Acts on Duck.ai voice-chat failures forwarded from the JS bridge. When the FE reports a
/// `NotAllowedError` and the OS has actually denied microphone access to the app, this
/// surfaces the system-disabled remediation popover anchored to the address-bar shield so
/// the user can open System Settings → Privacy. Other reasons are logged as `other` for
/// telemetry and otherwise ignored.
///
/// Dependencies are injected to make the class fully unit-testable:
/// - `microphoneAuthorizationStatusProvider` for the OS state
/// - `permissionCenterPresenter` for the popover surface
/// - `pixelFiring` for telemetry
final class DuckAiVoiceChatFailureHandler: DuckAiVoiceChatFailureHandling {

    /// FE-side error name we care about. Matches `MediaDeviceError.NotAllowedError` from the
    /// MediaDevices spec — the only reason that genuinely indicates a permission denial.
    static let notAllowedErrorReason = "NotAllowedError"

    private let microphoneAuthorizationStatusProvider: () -> AVAuthorizationStatus
    private let permissionCenterPresenter: DuckAiVoiceChatPermissionCenterPresenting
    private let pixelFiring: PixelFiring?

    init(microphoneAuthorizationStatusProvider: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
         permissionCenterPresenter: DuckAiVoiceChatPermissionCenterPresenting,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.microphoneAuthorizationStatusProvider = microphoneAuthorizationStatusProvider
        self.permissionCenterPresenter = permissionCenterPresenter
        self.pixelFiring = pixelFiring
    }

    @MainActor
    func handleVoiceChatStartFailed(reason: String, sourceWebView: WKWebView?) {
        handleStartFailed(reason: reason, source: .voiceChat, sourceWebView: sourceWebView)
    }

    @MainActor
    func handleDictationStartFailed(reason: String, sourceWebView: WKWebView?) {
        handleStartFailed(reason: reason, source: .dictation, sourceWebView: sourceWebView)
    }

    @MainActor
    private func handleStartFailed(reason: String, source: DuckAiMicPermissionSource, sourceWebView: WKWebView?) {
        // `aiChatVoiceChatStartFailed` is voice-chat-only telemetry; dictation has no dedicated
        // pixel yet, so don't count its failures here (mirrors the `.micOsDenied` decision in
        // `AddressBarButtonsViewController`).
        func fireOtherFailureIfNeeded() {
            guard source == .voiceChat else { return }
            pixelFiring?.fire(
                AIChatPixel.aiChatVoiceChatStartFailed(reason: .other),
                frequency: .dailyAndCount
            )
        }

        guard reason == Self.notAllowedErrorReason else {
            fireOtherFailureIfNeeded()
            return
        }

        let isOSMicrophoneDenied: Bool = {
            switch microphoneAuthorizationStatusProvider() {
            case .denied, .restricted: return true
            case .authorized, .notDetermined: return false
            @unknown default: return false
            }
        }()

        guard isOSMicrophoneDenied else {
            fireOtherFailureIfNeeded()
            return
        }

        // Dedupe: skip if the popover is already on screen for this webView (or any, since
        // the popover is window-scoped). Avoids stacking when the user mashes the voice button.
        guard !permissionCenterPresenter.isPermissionCenterPresented(for: sourceWebView) else { return }

        // `.micOsDenied` is fired by the receiver (`AddressBarButtonsViewController`) after it
        // dedupes against its own popover state — that's the ground truth for "we actually
        // surfaced the remediation popover". Firing here would over-count on rapid FE retries
        // because the production presenter's `isPermissionCenterPresented` always returns
        // `false`.
        permissionCenterPresenter.presentPermissionCenter(for: sourceWebView, source: source)
    }
}

// MARK: - Presenter abstraction

protocol DuckAiVoiceChatPermissionCenterPresenting: AnyObject {
    @MainActor func isPermissionCenterPresented(for webView: WKWebView?) -> Bool
    @MainActor func presentPermissionCenter(for webView: WKWebView?, source: DuckAiMicPermissionSource)
}

/// Notification-based presenter used in production: posts a notification carrying the source
/// `WKWebView`. `AddressBarButtonsViewController` observes it on the relevant window and
/// opens the Permission Center popover if the webView matches its selected tab and the
/// popover isn't already shown.
final class NotificationCenterPermissionCenterPresenter: DuckAiVoiceChatPermissionCenterPresenting {

    private let notificationCenter: NotificationCenter
    /// External hook for the dedupe probe — supplied by whoever wires this up so the
    /// failure handler can query the address-bar layer without depending on AppKit.
    private let isPresentedProvider: @MainActor (WKWebView?) -> Bool

    init(notificationCenter: NotificationCenter = .default,
         isPresentedProvider: @escaping @MainActor (WKWebView?) -> Bool) {
        self.notificationCenter = notificationCenter
        self.isPresentedProvider = isPresentedProvider
    }

    @MainActor
    func isPermissionCenterPresented(for webView: WKWebView?) -> Bool {
        isPresentedProvider(webView)
    }

    @MainActor
    func presentPermissionCenter(for webView: WKWebView?, source: DuckAiMicPermissionSource) {
        notificationCenter.post(
            name: .aiChatVoiceChatPermissionCenterRequested,
            object: webView,
            userInfo: [NotificationCenterPermissionCenterPresenter.sourceUserInfoKey: source]
        )
    }

    /// `userInfo` key carrying the `DuckAiMicPermissionSource` on
    /// `aiChatVoiceChatPermissionCenterRequested`. Absent/unrecognized values default to
    /// `.voiceChat` at the receiver.
    static let sourceUserInfoKey = "source"
}

extension NSNotification.Name {
    /// Posted when Duck.ai voice chat failed due to OS-level microphone denial and native
    /// should surface the system-disabled remediation popover. `object` is the source
    /// `WKWebView`. The receiver (`AddressBarButtonsViewController`) anchors the popover to
    /// the address-bar shield, which is kept visible by `isDuckAiVoiceChatSystemMicDenied`
    /// for the duration of the OS-denied state.
    static let aiChatVoiceChatPermissionCenterRequested: NSNotification.Name =
        Notification.Name(rawValue: "com.duckduckgo.aiChat.voiceChatPermissionCenterRequested")
}
