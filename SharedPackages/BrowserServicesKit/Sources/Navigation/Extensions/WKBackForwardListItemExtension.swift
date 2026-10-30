//
//  WKBackForwardListItemExtension.swift
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
import WebKit

public extension WKBackForwardListItem {

    /// Safe Optional `url: URL` getter:
    /// `WKBackForwardListItem.url` is imported as non-optional, but WebKit's
    /// implementation can return nil for null or invalid underlying URLs,
    /// trapping Swift's unconditional `NSURL` → `URL` bridge. Reading via the
    /// getter selector keeps the value optional so the conditional `as? URL`
    /// cast safely returns nil instead of crashing.
    /// See: https://app.asana.com/1/137249556945/project/1201037661562251/task/1214602405943382
    var safeURL: URL? {
        _=WKBackForwardListItem.addSafetyCheckForSafeURLUsageOnce
        return self.perform(#selector(getter: WKBackForwardListItem.url))?.takeUnretainedValue() as? URL
    }

    /// Safe Optional `initialURL: URL` getter, for the same reason as `safeURL`.
    var safeInitialURL: URL? {
        _=WKBackForwardListItem.addSafetyCheckForSafeURLUsageOnce
        return self.perform(#selector(getter: WKBackForwardListItem.initialURL))?.takeUnretainedValue() as? URL
    }

#if DEBUG
    private static var ignoredURLUsageSymbols = Set<String>()

    // ensure `.safeURL` and `.safeInitialURL` are used and not `.url` and `.initialURL`
    static var addSafetyCheckForSafeURLUsageOnce: Void = {
        for (original, swizzled) in [(#selector(getter: WKBackForwardListItem.url), #selector(WKBackForwardListItem.swizzledURL)),
                                     (#selector(getter: WKBackForwardListItem.initialURL), #selector(WKBackForwardListItem.swizzledInitialURL))] {
            let originalMethod = class_getInstanceMethod(WKBackForwardListItem.self, original)!
            let swizzledMethod = class_getInstanceMethod(WKBackForwardListItem.self, swizzled)!
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }

        // ignore `-[WKBackForwardListItem description]`
        ignoredURLUsageSymbols.insert("-[WKBackForwardListItem description]")
    }()

    @objc dynamic private func swizzledURL() -> URL? {
        Self.checkSafeURLUsage(unsafe: "url", safe: "safeURL", calledFrom: "swizzledURL")
        return self.swizzledURL() // call the original
    }

    @objc dynamic private func swizzledInitialURL() -> URL? {
        Self.checkSafeURLUsage(unsafe: "initialURL", safe: "safeInitialURL", calledFrom: "swizzledInitialURL")
        return self.swizzledInitialURL() // call the original
    }

    private static func checkSafeURLUsage(unsafe: String, safe: String, calledFrom swizzledSymbol: String) {
        let symbol = callingSymbol(after: swizzledSymbol)
        // `safeURL`/`safeInitialURL` read the getters through `perform(_:)`, which may not leave its own frame
        let isSafeGetter = symbol.contains("performSelector") || symbol.contains("safeURL") || symbol.contains("safeInitialURL")
        guard !isSafeGetter, !isWebExtensionSymbol(symbol), !isWebKitInternalSymbol(symbol),
              ignoredURLUsageSymbols.insert(symbol).inserted else { return }

        breakByRaisingSigInt("Don‘t use `WKBackForwardListItem.\(unsafe)` as it has incorrect nullability\n" +
                             "Use `WKBackForwardListItem.\(safe)` instead")
    }

#else
    static var addSafetyCheckForSafeURLUsageOnce: Void { () }
#endif

}
