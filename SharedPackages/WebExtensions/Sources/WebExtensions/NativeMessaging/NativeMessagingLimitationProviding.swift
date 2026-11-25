//
//  NativeMessagingLimitationProviding.swift
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

import Foundation

/// What the app knows about extensions that tried to talk to an app on the Mac in a build that can't allow it,
/// such as the App Store build. Every method answers `false` or does nothing in builds that allow it.
public protocol NativeMessagingLimitationProviding: AnyObject {
    @MainActor func hasHitNativeMessagingLimitation(identifier: String) -> Bool
    @MainActor func isNativeMessagingAlertSuppressed(identifier: String) -> Bool
    @MainActor func suppressNativeMessagingAlert(identifier: String)
    /// The bounded value extension pixels report for the extension.
    @MainActor func pixelExtension(identifier: String) -> WebExtensionPixelExtension
}
