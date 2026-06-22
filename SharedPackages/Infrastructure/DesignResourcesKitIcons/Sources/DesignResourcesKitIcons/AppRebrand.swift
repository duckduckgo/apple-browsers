//
//  AppRebrand.swift
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

/// Global, app-wide app-rebrand state used to switch between legacy and new visuals.
///
/// **Naming convention in asset catalogs**
/// - The plain imageset name (e.g. `Fire-128.imageset`) holds the **new** (rebranded) visual.
/// - A sibling `<name>-legacy.imageset` holds the **old** visual.
///
/// **How callers use it**
/// - DesignSystem accessors and the `Image(rebrandable:)` initializer read
///   `AppRebrand.isAppRebranded` internally, so call sites never have to write a ternary.
/// - The default value is `false`, meaning the legacy variants are returned. The host app should
///   override this at launch by setting the closure to a live feature-flag lookup, e.g.:
///
///   ```swift
///   AppRebrand.isAppRebranded = {
///       AppDependencyProvider.shared.featureFlagger.isFeatureOn(.appRebranding)
///   }
///   ```
///
/// Extension targets that don't have a `FeatureFlagger` of their own can leave this at the
/// default `{ false }`, in which case they'll always show the legacy visuals.
public enum AppRebrand {

    /// Returns `true` when the app should display the rebranded visuals; `false` for legacy.
    /// Set this once at launch from the host app.
    nonisolated(unsafe) public static var isAppRebranded: () -> Bool = { false }
}
