//
//  WebExtensionLifecycleEvent.swift
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

/// Identifies the operation responsible for reloading a web extension.
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionReloadTrigger: Equatable, Sendable {
    /// Browser data clearing unloaded and then restored extensions.
    case dataClearing
    /// A scriptlet update required the affected extension to reload.
    case scriptletUpdate
    /// A caller explicitly requested an extension reload.
    case explicit
}

/// Describes observable load and reload transitions produced by `WebExtensionManager`.
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionLifecycleEvent: Equatable, Sendable {
    /// The extension was loaded without replacing an existing context.
    case loaded(identifier: String, type: DuckDuckGoWebExtensionType?)
    /// The manager is about to replace the extension context.
    case willReload(identifier: String, type: DuckDuckGoWebExtensionType?, trigger: WebExtensionReloadTrigger)
    /// The manager successfully replaced the extension context.
    case reloaded(identifier: String, type: DuckDuckGoWebExtensionType?, trigger: WebExtensionReloadTrigger)
    /// The reload operation failed before the replacement context became active.
    case reloadFailed(identifier: String, type: DuckDuckGoWebExtensionType?, trigger: WebExtensionReloadTrigger)
}
