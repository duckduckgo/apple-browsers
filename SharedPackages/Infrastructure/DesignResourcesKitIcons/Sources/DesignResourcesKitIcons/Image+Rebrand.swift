//
//  Image+Rebrand.swift
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

#if canImport(UIKit)
import SwiftUI
import UIKit

public extension Image {

    /// Loads `name` from `bundle`, falling back to a `<name>-legacy` variant when the app
    /// is **not** in the rebranded state (per `AppRebrand.isAppRebranded`).
    ///
    /// In asset catalogs the convention is:
    /// - `<name>.imageset` holds the **new** (rebranded) artwork.
    /// - `<name>-legacy.imageset` holds the **old** artwork.
    ///
    /// When `AppRebrand.isAppRebranded()` returns `true`, this initializer uses `<name>` directly.
    /// When it returns `false`, this initializer tries `<name>-legacy` first and falls back to
    /// `<name>` if no legacy variant exists — so it is safe to use for any asset name regardless
    /// of whether a legacy twin ships alongside it.
    ///
    /// - Parameters:
    ///   - rebrandable: The base asset name (the new/rebranded artwork's imageset name).
    ///   - bundle: The bundle to look the asset up in. Defaults to the main bundle.
    init(rebrandable name: String, bundle: Bundle? = nil) {
        if AppRebrand.isAppRebranded() {
            self.init(name, bundle: bundle)
        } else if UIImage(named: "\(name)-legacy", in: bundle, with: nil) != nil {
            self.init("\(name)-legacy", bundle: bundle)
        } else {
            self.init(name, bundle: bundle)
        }
    }
}
#endif
