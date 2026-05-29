//
//  DesignSystemRebrand.swift
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

/// Global, app-wide app-rebrand state used to switch design-system colors between their legacy and
/// rebranded values. The host app should override this at launch by setting the closure to a live feature-flag lookup, e.g.:
///
/// ```swift
/// DesignSystemRebrand.isAppRebranded = {
///     AppDependencyProvider.shared.featureFlagger.isFeatureOn(.appRebranding)
/// }
/// ```
///
public enum DesignSystemRebrand {

    /// Returns `true` when the app should display rebranded design-system colors; `false` for legacy.
    /// Set this once at launch from the host app.
    nonisolated(unsafe) public static var isAppRebranded: () -> Bool = { false }
}
