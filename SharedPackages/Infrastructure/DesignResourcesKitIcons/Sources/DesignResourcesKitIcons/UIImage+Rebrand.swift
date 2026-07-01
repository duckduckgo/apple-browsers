//
//  UIImage+Rebrand.swift
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
import UIKit

public extension UIImage {

    /// UIKit counterpart of `Image(rebrandable:)`.
    ///
    /// - Parameters:
    ///   - rebrandable: The base asset name (the new/rebranded artwork's imageset name).
    ///   - bundle: The bundle to look the asset up in. Defaults to the main bundle.
    convenience init?(rebrandable name: String, in bundle: Bundle? = nil) {
        var imageName = name

        if AppRebrand.isAppRebranded() == false {
            let legacyName = "\(name)-legacy"
            if UIImage(named: legacyName, in: bundle, with: nil) != nil {
                imageName = legacyName
            }
        }

        self.init(named: imageName, in: bundle, with: nil)
    }
}
#endif
