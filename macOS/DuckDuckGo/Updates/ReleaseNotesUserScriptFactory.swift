//
//  ReleaseNotesUserScriptFactory.swift
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

import Common
import Foundation
import Persistence
import PixelKit
import UserScript

/// Protocol that concrete updater packages implement for the factory pattern.
///
/// SparkleAppUpdater extends this to provide its implementation. The extension
/// is only compiled when that package is linked.
public protocol ReleaseNotesUserScriptFactoryBuilder {
    /// Creates a release notes user script with required dependencies.
    func makeUserScript(
        updateController: any SparkleUpdateController,
        pixelFiring: PixelFiring?,
        keyValueStore: ThrowingKeyValueStoring,
        releaseNotesURL: URL
    ) -> Subfeature
}

/// Factory for creating ReleaseNotesUserScript based on build configuration.
///
/// This uses a protocol extension pattern: only the package linked at build time
/// (SparkleAppUpdater) extends this factory to provide an implementation.
///
/// **How it works:**
/// 1. Sparkle builds link SparkleAppUpdater which extends this factory
/// 2. App Store builds don't link SparkleAppUpdater, so no extension exists
/// 3. Casting to the builder protocol succeeds for Sparkle, fails for App Store
///
/// **Usage:**
/// ```swift
/// let factory = ReleaseNotesUserScriptFactory()
/// if let script = (factory as? ReleaseNotesUserScriptFactoryBuilder)?.makeUserScript(...) {
///     // Script available (Sparkle build)
/// }
/// ```
public struct ReleaseNotesUserScriptFactory {
    public init() {}
}
