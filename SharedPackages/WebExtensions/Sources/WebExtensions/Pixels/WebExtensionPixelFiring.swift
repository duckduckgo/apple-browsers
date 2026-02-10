//
//  WebExtensionPixelFiring.swift
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

import Foundation

/// Events that can be fired for web extension management.
public enum WebExtensionPixelEvent {
    case installed
    case installError(error: Error)
    case uninstalled
    case uninstallError(error: Error)
    case uninstalledAll
    case uninstallAllError(error: Error)
    case loaded
    case loadError(error: Error)
}

/// Protocol for firing web extension pixels.
/// Implement this protocol in each platform to wire up to the platform-specific pixel system.
public protocol WebExtensionPixelFiring {
    func fire(_ event: WebExtensionPixelEvent)
}

/// Default no-op implementation for when pixel firing is not needed.
public struct NoOpWebExtensionPixelFiring: WebExtensionPixelFiring {
    public init() {}
    public func fire(_ event: WebExtensionPixelEvent) {}
}
