//
//  MockVariantManager.swift
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

import BrowserServicesKit
import Foundation

public class MockVariantManager: VariantManager {

    public var isSupportedReturns = false {
        didSet {
            let newValue = isSupportedReturns
            isSupportedBlock = { _ in return newValue }
        }
    }

    public var isSupportedBlock: (FeatureName) -> Bool

    public var currentVariant: Variant?

    public init(isSupportedReturns: Bool = false, currentVariant: Variant? = nil) {
        self.isSupportedReturns = isSupportedReturns
        self.isSupportedBlock = { _ in return isSupportedReturns }
        self.currentVariant = currentVariant
    }

    public func assignVariantIfNeeded(_ newInstallCompletion: (VariantManager) -> Void) {
    }

    public func isSupported(feature: FeatureName) -> Bool {
        return isSupportedBlock(feature)
    }

}
