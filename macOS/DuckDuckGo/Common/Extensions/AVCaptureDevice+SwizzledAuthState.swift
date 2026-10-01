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

import Foundation
import AVFoundation

/// Temporarily intercepts `AVCaptureDevice.authorizationStatus(for:)` while WebKit handles a camera/microphone request.
///
/// Why: before WebKit asks its UI delegate (`webView(_:requestMediaCapturePermissionFor:...)`) about a
/// `getUserMedia` call, it reads `AVCaptureDevice.authorizationStatus(for:)` itself. When macOS has denied
/// access, WebKit rejects the call right there and the delegate never runs, so the app can neither learn
/// which device was requested nor show its own prompt.
///
/// How it works:
/// 1. `PermissionModel.prepareForMediaPermissionRequest()` calls `swizzleAuthorizationStatusForMediaType(with:)`
///    from WebKit's preflight callbacks (`checkUserMediaPermissionForURL` and `queryPermission`), before WebKit
///    reads the status. This exchanges the class method's implementation with `swizzled_authorizationStatus(for:)`
///    and stores the replacement closure.
/// 2. While installed, every main-thread `authorizationStatus(for:)` call gets the real macOS status and passes it
///    through the closure, which can change it. With `websitePermissionsPrompts` on, the closure reports
///    `.authorized`, so WebKit always reaches the delegate and the website prompt shows its System Settings step
///    instead. With the flag off, it records which devices macOS denied and leaves the status unchanged.
/// 3. The hook is process-wide and must not outlive the request. `PermissionModel` restores it when the request
///    reaches the delegate, once both devices have been checked, or after a 5-second fallback. Each install returns
///    an identifier, and `restoreAuthorizationStatusForMediaType(ifMatching:)` ignores stale identifiers, so a late
///    fallback can't remove a newer request's hook.
/// 4. App code that needs the real macOS status, such as `SystemPermissionManager` and the Duck.ai mic checks,
///    calls `systemAuthorizationStatus(for:)`, which bypasses the hook.
extension AVCaptureDevice {
    private typealias AuthorizationStatusImplementation = @convention(c) (AnyClass, Selector, NSString) -> AVAuthorizationStatus

    /// The replacement closure while the hook is installed; `nil` means `authorizationStatus(for:)` is untouched.
    private static var authorizationStatusForMediaType: ((AVMediaType, inout AVAuthorizationStatus) -> Void)?
    /// Identifies the current installation, so only its owner (or an unconditional restore) can remove it.
    private static var authorizationStatusSwizzleID: UUID?
    private static var isSwizzled: Bool { authorizationStatusForMediaType != nil }

    private static let originalAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(authorizationStatus(for:)))
    }()
    private static let swizzledAuthorizationStatusForMediaType = {
        class_getClassMethod(AVCaptureDevice.self, #selector(swizzled_authorizationStatus(for:)))
    }()
    /// AVFoundation's own implementation, captured before the first exchange so it can be called directly
    /// whether or not the hook is installed.
    private static let systemAuthorizationStatusImplementation: AuthorizationStatusImplementation? = {
        guard let originalAuthorizationStatusForMediaType else { return nil }
        return unsafeBitCast(method_getImplementation(originalAuthorizationStatusForMediaType), to: AuthorizationStatusImplementation.self)
    }()

    /// Installs the hook and routes main-thread `authorizationStatus(for:)` calls through `replacement`.
    ///
    /// - Parameter replacement: Receives the media type and the real macOS status, and may change the status.
    /// - Returns: An identifier for `restoreAuthorizationStatusForMediaType(ifMatching:)`, or `nil` when a hook is
    ///   already installed. In that case the existing installation keeps running and the caller doesn't own it.
    @discardableResult
    static func swizzleAuthorizationStatusForMediaType(with replacement: @escaping ((AVMediaType, inout AVAuthorizationStatus) -> Void)) -> UUID? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !self.isSwizzled else { return nil }
        guard let originalAuthorizationStatusForMediaType = originalAuthorizationStatusForMediaType,
              let swizzledAuthorizationStatusForMediaType = swizzledAuthorizationStatusForMediaType,
              systemAuthorizationStatusImplementation != nil
        else {
            assertionFailure("Methods not available")
            return nil
        }

        method_exchangeImplementations(originalAuthorizationStatusForMediaType, swizzledAuthorizationStatusForMediaType)
        self.authorizationStatusForMediaType = replacement
        let identifier = UUID()
        authorizationStatusSwizzleID = identifier
        return identifier
    }

    /// Removes the hook so `authorizationStatus(for:)` returns the real macOS status again.
    ///
    /// - Parameter identifier: The identifier returned when the hook was installed. Pass it from delayed or
    ///   per-tab cleanup, so a stale call can't remove a newer installation. `nil` removes any installation.
    static func restoreAuthorizationStatusForMediaType(ifMatching identifier: UUID? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard self.isSwizzled else { return }
        guard identifier == nil || identifier == authorizationStatusSwizzleID else { return }
        guard let originalAuthorizationStatusForMediaType = originalAuthorizationStatusForMediaType,
              let swizzledAuthorizationStatusForMediaType = swizzledAuthorizationStatusForMediaType
        else {
            assertionFailure("Methods not available")
            return
        }

        method_exchangeImplementations(originalAuthorizationStatusForMediaType, swizzledAuthorizationStatusForMediaType)
        self.authorizationStatusForMediaType = nil
        authorizationStatusSwizzleID = nil
    }

    /// The real macOS authorization status, unaffected by the hook.
    ///
    /// App permission checks must use this instead of `authorizationStatus(for:)`: while a request is being
    /// intercepted, `authorizationStatus(for:)` can report `.authorized` even though macOS denied access.
    @objc dynamic
    static func systemAuthorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        guard let systemAuthorizationStatusImplementation else {
            assertionFailure("Authorization status implementation not available")
            return .denied
        }
        // Selector dispatch can race with restoring the hook; this implementation is captured before the first exchange.
        return systemAuthorizationStatusImplementation(self, #selector(authorizationStatus(for:)), mediaType.rawValue as NSString)
    }

    /// Runs as `authorizationStatus(for:)` while the hook is installed. Only main-thread calls are passed to the
    /// replacement closure, because WebKit's preflight runs there and the closure touches main-thread state.
    @objc dynamic private static func swizzled_authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        var result = systemAuthorizationStatus(for: mediaType)
        if Thread.isMainThread,
           let authorizationStatusForMediaType = Self.authorizationStatusForMediaType {
            authorizationStatusForMediaType(mediaType, &result)
        }
        return result
    }

}
