//
//  ScriptletConfiguration.swift
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

/// Bundles the dependencies for the scriptlet subsystem.
/// Pass to `WebExtensionManager` to enable automatic scriptlet management.
@available(macOS 15.4, iOS 18.4, *)
public struct ScriptletConfiguration {

    public let provider: ScriptletProviding
    public let installationTracker: ScriptletInstallationTracking
    public let installer: ScriptletInstalling
    public let pixelFiring: WebExtensionPixelFiring
    public let cacheRootDirectory: URL

    public init(
        provider: ScriptletProviding,
        installationTracker: ScriptletInstallationTracking,
        installer: ScriptletInstalling = ScriptletInstaller(),
        pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring(),
        cacheRootDirectory: URL
    ) {
        self.provider = provider
        self.installationTracker = installationTracker
        self.installer = installer
        self.pixelFiring = pixelFiring
        self.cacheRootDirectory = cacheRootDirectory
    }
}
