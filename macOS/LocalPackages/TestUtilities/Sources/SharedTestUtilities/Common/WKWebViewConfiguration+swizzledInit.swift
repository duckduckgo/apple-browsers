//
//  WKWebViewConfiguration+swizzledInit.swift
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

import WebKit

public extension WKWebViewConfiguration {

    private static var processPoolGetter: (() -> WKProcessPool?)?

    static func swizzleInitOnce(processPool: @escaping @autoclosure () -> WKProcessPool?) {
        guard processPoolGetter == nil else { return }
        processPoolGetter = processPool
        _=swizzleInitOnce
    }

    private static var swizzleInitOnce: Void = {
        let initMethod = class_getInstanceMethod(WKWebViewConfiguration.self, #selector(NSObject.init))!
        let swizzledInitMethod = class_getInstanceMethod(WKWebViewConfiguration.self, #selector(WKWebViewConfiguration.swizzled_init))!

        method_exchangeImplementations(initMethod, swizzledInitMethod)
    }()

    private static var processPoolInitArg: WKProcessPool?

    @objc private dynamic func swizzled_init() -> WKWebViewConfiguration {
        let configuration = swizzled_init()
        if let processPool = Self.processPoolInitArg {
            configuration.processPool = processPool
        } else if let processPool = Self.processPoolGetter?() {
            configuration.processPool = processPool
        }
        return configuration
    }

    convenience init(processPool: WKProcessPool) {
        Self.processPoolInitArg = processPool
        defer {
            Self.processPoolInitArg = nil
        }
        self.init()
    }

}
