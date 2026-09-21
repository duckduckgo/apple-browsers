//
//  WKWebView+SitePermissionCaptureState.swift
//  DuckDuckGo
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

import WebKit

/// The web view's current capture activity, independent of any saved permission choice.
public enum SitePermissionCaptureState: Equatable, Sendable {
    /// No capture is running. The initial state, also used after capture ends (`WKMediaCaptureState.none`).
    case inactive
    /// The web view is actively using the camera or microphone (`WKMediaCaptureState.active`).
    case active
    /// An existing capture session is muted and can resume (`WKMediaCaptureState.muted`),
    /// for example after calling `setCameraCaptureState(.muted)` or `setMicrophoneCaptureState(.muted)`.
    case paused

    init(_ state: WKMediaCaptureState) {
        switch state {
        case .none:
            self = .inactive
        case .active:
            self = .active
        case .muted:
            self = .paused
        @unknown default:
            self = .inactive
        }
    }
}

extension WKWebView {

    var sitePermissionCameraCaptureState: SitePermissionCaptureState {
        SitePermissionCaptureState(cameraCaptureState)
    }

    var sitePermissionMicrophoneCaptureState: SitePermissionCaptureState {
        SitePermissionCaptureState(microphoneCaptureState)
    }

    @MainActor
    public func revokeSitePermissions(_ permissionTypes: Set<SitePermissionType>) {
        if permissionTypes.contains(.camera) {
            setCameraCaptureState(.none, completionHandler: {})
        }
        if permissionTypes.contains(.microphone) {
            setMicrophoneCaptureState(.none, completionHandler: {})
        }
    }
}
