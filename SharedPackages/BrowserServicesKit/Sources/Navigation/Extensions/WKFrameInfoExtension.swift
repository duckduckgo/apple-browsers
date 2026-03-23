//
//  WKFrameInfoExtension.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import WebKit

public extension WKFrameInfo {

    internal static var defaultMainFrameHandle: UInt64 = 4
    internal static var defaultNonMainFrameHandle: UInt64 = 9

    // prevent exception if private API keys go missing
    override func value(forUndefinedKey key: String) -> Any? {
        assertionFailure("valueForUndefinedKey: \(key)")
        return nil
    }

#if _FRAME_HANDLE_ENABLED
    @nonobjc var handle: FrameHandle {
        guard let handle = self.value(forKey: "handle") as? FrameHandle else {
            assertionFailure("WKFrameInfo.handle is missing")
            return self.isMainFrame ? (webView?.mainFrameHandle ?? .fallbackMainFrameHandle) : .fallbackNonMainFrameHandle
        }
        return handle
    }
#endif

    /// Safe Optional `request: URLRequest` getter:
    /// .request of a new Frame can be `null`, see https://app.asana.com/0/0/1203965979591356/f
    var safeRequest: URLRequest? {
        _=WKFrameInfo.addSafetyCheckForSafeRequestUsageOnce
        return self.perform(#selector(getter: request))?.takeUnretainedValue() as? URLRequest
    }

#if DEBUG
    private static var ignoredRequestUsageSymbols = Set<String>()

    // ensure `.safeRequest` is used and not `.request`
    static var addSafetyCheckForSafeRequestUsageOnce: Void = {
        let originalRequestMethod = class_getInstanceMethod(WKFrameInfo.self, #selector(getter: WKFrameInfo.request))!
        let swizzledRequestMethod = class_getInstanceMethod(WKFrameInfo.self, #selector(WKFrameInfo.swizzledRequest))!
        method_exchangeImplementations(originalRequestMethod, swizzledRequestMethod)

        // ignore `request` selector calls from `safeRequest` itself
        let callingSymbol = callingSymbol(after: "addSafetyCheckForSafeRequestUsageOnce")
        ignoredRequestUsageSymbols.insert(callingSymbol)
        // ignore `-[WKFrameInfo description]`
        ignoredRequestUsageSymbols.insert("-[WKFrameInfo description]")
    }()

    @objc dynamic private func swizzledRequest() -> URLRequest? {
        func fileLine(file: StaticString = #file, line: Int = #line) -> String {
            return "\(("\(file)" as NSString).lastPathComponent):\(line + 1)"
        }

        let symbol = callingSymbol()
        if !isWebExtensionSymbol(symbol) && !isWebKitInternalSymbol(symbol) && Self.ignoredRequestUsageSymbols.insert(symbol).inserted {
            breakByRaisingSigInt("Don‘t use `WKFrameInfo.request` as it has incorrect nullability\n" +
                                 "Use `WKFrameInfo.safeRequest` instead")
        }

        return self.swizzledRequest() // call the original
    }

    private func isWebExtensionSymbol(_ symbol: String) -> Bool {
        symbol.contains("WebExtension")
    }

    /// WebKit internal calls (e.g. from `requestMediaCapturePermissionFor`) access `.request`
    /// directly. These frames lack debug symbols and `callingSymbol()` returns a module UUID
    /// instead of a readable name — we should not assert on these.
    private func isWebKitInternalSymbol(_ symbol: String) -> Bool {
        // WebKit internal frames are not symbolicated in debug builds,
        // so callingSymbol() returns the module UUID (e.g. "8338D2BF-1C6B-3B01-B979-A50F6D272044")
        // rather than a function name like "-[SomeClass method]" or "$sSwiftMangled..."
        !symbol.hasPrefix("-[") && !symbol.hasPrefix("$s") && !symbol.hasPrefix("_$s") && UUID(uuidString: symbol) != nil
    }

#else
    static var addSafetyCheckForSafeRequestUsageOnce: Void { () }
#endif

}
