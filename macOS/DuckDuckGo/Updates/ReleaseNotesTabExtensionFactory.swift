//
//  ReleaseNotesTabExtensionFactory.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation
import Navigation
import WebKit

/// Public protocol for ReleaseNotesTabExtension functionality.
open class ReleaseNotesTabExtensionBase: ReleaseNotesTabExtensionProtocol {
    public func getPublicProtocol() -> ReleaseNotesTabExtensionProtocol { self }
    public init() {}
}

/// Protocol that concrete updater packages implement for the factory pattern.
///
/// SparkleAppUpdater extends this to register its implementation. The extension
/// is only compiled when that package is linked, making the factory available
/// only in Sparkle builds.
public protocol ReleaseNotesTabExtensionFactoryBuilder {
    /// Creates a release notes tab extension with required dependencies.
    func makeExtension(
        updateController: any SparkleUpdateController,
        releaseNotesURL: URL,
        scriptsPublisher: some Publisher<some ReleaseNotesUserScriptProvider, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>
    ) -> ReleaseNotesTabExtensionBase
}

/// Factory for creating ReleaseNotesTabExtension based on build configuration.
///
/// This uses a protocol extension pattern: only the package linked at build time
/// (SparkleAppUpdater) extends this factory to provide an implementation.
///
/// **How it works:**
/// 1. Sparkle builds link SparkleAppUpdater which extends this factory
/// 2. App Store builds don't link SparkleAppUpdater, so no extension exists
/// 3. Calling `make()` returns an extension for Sparkle, nil for App Store
///
/// **Usage:**
/// ```swift
/// let factory = ReleaseNotesTabExtensionFactory()
/// if let ext = factory.make(updateController: ...) {
///     // Extension available (Sparkle build)
/// }
/// ```
public struct ReleaseNotesTabExtensionFactory {
    public init() {}
}
