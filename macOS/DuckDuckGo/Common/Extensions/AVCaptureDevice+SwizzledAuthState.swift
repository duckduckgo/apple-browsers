//
//  AVCaptureDevice+SwizzledAuthState.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

/// Intercepts WebKit's `AVCaptureDevice.authorizationStatus(for:)` check during a camera/microphone request.
///
/// Why: before WebKit asks its UI delegate (`webView(_:requestMediaCapturePermissionFor:...)`) about a getUserMedia
/// call, it checks macOS access itself. When macOS has denied access, WebKit rejects the call right there and the
/// delegate never runs, so the app can't show its own prompt (or learn which device was requested). When macOS
/// hasn't decided yet, WebKit shows the macOS prompt itself, before the website prompt.
/// `queryPermission` can't replace the hook: WebKit only uses a granted answer and checks macOS access whatever it returns.
///
/// How: WebKit's preflight callback (`queryPermission` since Safari 26's WebKit, `checkUserMediaPermissionForURL`
/// before that) sets a one-shot token per media type here, and WebKit's following status check of that type uses it up:
/// - `authorizeNextStatusCheck`: the check reports `.authorized`, so WebKit reaches the delegate and the website prompt.
/// - `observeNextStatusCheck` (WebKit before Safari 26, without website prompts): the real status is passed to a callback.
/// Tokens expire after 3s and are dropped by `resetAuthorizationStatusOverrides(owner:)` once the request reaches the
/// delegate, so app reads outside that window get the real macOS status.
extension AVCaptureDevice {

    private struct AuthorizationStatusOverride {
        let timestamp: Date
        let owner: ObjectIdentifier
        /// WebKit before Safari 26, without website prompts: receives the real status instead of reporting `.authorized`.
        @available(macOS, deprecated: 26.0, message: "Only used by observeNextStatusCheck. Remove when macOS 26 is the minimum.")
        var callback: ((AVMediaType, AVAuthorizationStatus) -> Void)?
    }

    private static let authorizationStatusOverrideTimeout: TimeInterval = 3
    @MainActor
    private static var authorizationStatusOverrides = [AVMediaType: AuthorizationStatusOverride](minimumCapacity: 2)

    /// Installs the `authorizationStatus(for:)` hook; it stays installed and passes through when no token is set.
    static let authorizationStatusSwizzle: Void = {
        guard let original = class_getClassMethod(AVCaptureDevice.self, #selector(authorizationStatus(for:))),
              let swizzled = class_getClassMethod(AVCaptureDevice.self, #selector(swizzled_authorizationStatus(for:)))
        else {
            assertionFailure("Methods not available")
            return
        }
        method_exchangeImplementations(original, swizzled)
    }()

    /// Makes the next `authorizationStatus(for:)` check of each of `mediaTypes` report `.authorized` if made in time.
    /// Replaces previous tokens for these media types, whoever set them.
    @MainActor
    static func authorizeNextStatusCheck(for mediaTypes: Set<AVMediaType>, owner: ObjectIdentifier, timestamp: Date = Date()) {
        setAuthorizationStatusOverride(AuthorizationStatusOverride(timestamp: timestamp, owner: owner), for: mediaTypes)
    }

    /// Passes the real status of the next `authorizationStatus(for:)` check of each of `mediaTypes` to `callback` if made in time.
    /// Replaces previous tokens for these media types, whoever set them.
    @available(macOS, deprecated: 26.0, message: "Used by checkUserMediaPermission for WebKit before Safari 26. Remove when macOS 26 is the minimum.")
    @MainActor
    static func observeNextStatusCheck(for mediaTypes: Set<AVMediaType>,
                                       owner: ObjectIdentifier,
                                       callback: @escaping (AVMediaType, AVAuthorizationStatus) -> Void) {
        setAuthorizationStatusOverride(AuthorizationStatusOverride(timestamp: Date(), owner: owner, callback: callback), for: mediaTypes)
    }

    @MainActor
    private static func setAuthorizationStatusOverride(_ token: AuthorizationStatusOverride, for mediaTypes: Set<AVMediaType>) {
        _=authorizationStatusSwizzle
        for mediaType in mediaTypes {
            authorizationStatusOverrides[mediaType] = token
        }
    }

    /// Drops the tokens set by `owner`, or all of them when `owner` is nil.
    @MainActor
    static func resetAuthorizationStatusOverrides(owner: ObjectIdentifier? = nil) {
        for (mediaType, token) in authorizationStatusOverrides where owner == nil || token.owner == owner {
            authorizationStatusOverrides.removeValue(forKey: mediaType)
        }
    }

    @MainActor
    @objc dynamic static func swizzled_authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        let original = self.swizzled_authorizationStatus(for: mediaType) // call the original
        // Each token is consumed by the first check; an outdated one is dropped without applying it.
        guard Thread.isMainThread,
              let token = authorizationStatusOverrides.removeValue(forKey: mediaType),
              Date().timeIntervalSince(token.timestamp) < authorizationStatusOverrideTimeout else { return original }
        // Return .authorized here, when the override token is set,
        // so WebKit proceeds to media permission request without [always] requesting system permission.
        // ---
        // WebKit before Safari 26 without website prompts: replace with `return .authorized` when macOS 26 is the minimum
        guard let callback = token.callback else { return .authorized }
        callback(mediaType, original)
        return original
    }

}
