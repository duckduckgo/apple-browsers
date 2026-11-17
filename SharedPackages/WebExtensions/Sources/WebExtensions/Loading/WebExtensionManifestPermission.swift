//
//  WebExtensionManifestPermission.swift
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

/// Manifest permissions that Chrome warns users about. Settings lists the ones an extension declares.
///
/// Source: https://developer.chrome.com/docs/extensions/reference/permissions-list
public enum WebExtensionManifestPermission: String {
    case accessibilityFeaturesModify = "accessibilityFeatures.modify"
    case accessibilityFeaturesRead = "accessibilityFeatures.read"
    case bookmarks
    case clipboardRead
    case clipboardWrite
    case contentSettings
    case debugger
    case declarativeNetRequest
    case declarativeNetRequestFeedback
    case desktopCapture
    case downloads
    case downloadsOpen = "downloads.open"
    case downloadsUI = "downloads.ui"
    case favicon
    case geolocation
    case history
    case identityEmail = "identity.email"
    case management
    case nativeMessaging
    case notifications
    case pageCapture
    case privacy
    case proxy
    case readingList
    case sessions
    case systemStorage = "system.storage"
    case tabCapture
    case tabGroups
    case tabs
    case topSites
    case ttsEngine
    case webAuthenticationProxy
    case webNavigation
}
