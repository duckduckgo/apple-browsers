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

        // don‘t break twice
        if Self.ignoredRequestUsageSymbols.insert(callingSymbol()).inserted {
            breakByRaisingSigInt("Don‘t use `WKFrameInfo.request` as it has incorrect nullability\n" +
                                 "Use `WKFrameInfo.safeRequest` instead")
        }

        return self.swizzledRequest() // call the original
    }

#else
    static var addSafetyCheckForSafeRequestUsageOnce: Void { () }
#endif

}
