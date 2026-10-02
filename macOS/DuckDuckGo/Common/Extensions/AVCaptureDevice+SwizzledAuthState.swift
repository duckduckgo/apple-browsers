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

/// WebKit checks `AVCaptureDevice.authorizationStatus(for:)` before calling our media capture delegate and
/// rejects getUserMedia without asking us when it's `.denied`/`.restricted`. Its preceding delegate callback
/// sets a per-media-type token here, so the next status check made by WebKit reports `.authorized`.
extension AVCaptureDevice {

    private struct AuthorizationStatusOverride {
        let timestamp: Date
        let owner: ObjectIdentifier
        /// macOS 12: receives the real status instead of reporting `.authorized`.
        @available(macOS, deprecated: 13.0, message: "Only used by observeNextStatusCheck. Remove with macOS 12 support.")
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
    @available(macOS, deprecated: 13.0, message: "Used by the macOS 12 checkUserMediaPermission path. Remove with macOS 12 support.")
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
        // macOS 12 flow: replace to `return .authorized` when macOS 12 is dropped
        guard let callback = token.callback else { return .authorized }
        callback(mediaType, original)
        return original
    }

}
