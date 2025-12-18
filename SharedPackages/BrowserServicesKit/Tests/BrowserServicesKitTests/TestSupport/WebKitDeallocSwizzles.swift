//
//  WebKitDeallocSwizzles.swift
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
import ObjectiveC.runtime
import WebKit

extension WKFrameInfo {

    private static var isSwizzled = false
    private static let originalDealloc = { class_getInstanceMethod(WKFrameInfo.self, NSSelectorFromString("dealloc"))! }()
    private static let swizzledDealloc = { class_getInstanceMethod(WKFrameInfo.self, #selector(swizzled_dealloc))! }()

    static func swizzleDealloc() {
        guard !self.isSwizzled else { return }
        self.isSwizzled = true
        method_exchangeImplementations(originalDealloc, swizzledDealloc)
    }

    @objc
    func swizzled_dealloc() { }
}
