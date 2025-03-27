//
//  WKCustomHeaderFields.swift
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

import Foundation

#if _WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED
/// `_WKCustomHeaderFields` class bridge to use from Swift context
/// used to add custom request headers to `WKNavigationAction` before the request is sent
///
/// Usage within the Navigation framework in `decidePolicy(for: NavigationAction, preferences: inout NavigationPreferences)`
/// ```
/// if NavigationPreferences.customHeadersSupported,
///    let customHeaders = CustomHeaderFields(fields: ["X-Key": "Value"]) {
///     preferences.customHeaders = [customHeaders]
/// }
/// ```
///
/// Direct WebKit Usage in `decidePolicy(for: WKNavigationAction, preferences: WKWebpagePreferences)`
///  ```
///  if WKWebpagePreferences.customHeaderFieldsSupported,
///     let customHeaders = CustomHeaderFields(fields: ["X-Key": "Value"]) {
///      preferences.customHeaderFields = [customHeaders]
///  }
///  ```
///
///  - Note: Obj-C bridging is used to make this data-storage struct implicitly converted into `_WKCustomHeaderFields` 
///  when passed to the WK Obj-C layer hiding the `NSClassFromString`-backed object allocation and and setting values by key
public struct CustomHeaderFields: _ObjectiveCBridgeable, Hashable {

    public var fields: [String: String]
    public var thirdPartyDomains: [String]

    public init?(fields: [String: String] = [:], thirdPartyDomains: [String] = []) {
        guard Self.objcClass != nil else { return nil }
        self.fields = fields
        self.thirdPartyDomains = thirdPartyDomains
    }

    private static let className = "WKCustomHeaderFields"
    private static let objcClass: AnyClass! = NSClassFromString("_" + Self.className) ?? NSClassFromString(Self.className)
    private static let fieldsKey = "fields"
    private static let thirdPartyDomainsKey = "thirdPartyDomains"

    // swiftlint:disable identifier_name

    public func _bridgeToObjectiveC() -> AnyObject {
        let obj = Self.objcClass.alloc().perform(#selector(NSObject.init)).takeUnretainedValue()
        if obj.responds(to: NSSelectorFromString(Self.fieldsKey)) {
            obj.setValue(fields, forKey: Self.fieldsKey)
        } else {
            assertionFailure("\(Self.className) does not respond to \(Self.fieldsKey)")
        }
        if obj.responds(to: NSSelectorFromString(Self.thirdPartyDomainsKey)) {
            obj.setValue(thirdPartyDomains, forKey: Self.thirdPartyDomainsKey)
        } else {
            assertionFailure("\(Self.className) does not respond to \(Self.thirdPartyDomainsKey)")
        }

        return obj
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: AnyObject, result output: inout CustomHeaderFields?) -> Bool {
        guard source.responds(to: #selector(NSObject.className)),
              source.className == "_" + Self.className || source.className == Self.className,
              var result = CustomHeaderFields() else { return false }

        if source.responds(to: NSSelectorFromString(Self.fieldsKey)),
            let fields = source.value(forKey: Self.fieldsKey) as? [String: String] {

            result.fields = fields
        } else {
            assertionFailure("\(Self.className) does not respond to \(Self.fieldsKey)")
        }

        if source.responds(to: NSSelectorFromString(Self.thirdPartyDomainsKey)),
           let thirdPartyDomains = source.value(forKey: Self.thirdPartyDomainsKey) as? [String] {

            result.thirdPartyDomains = thirdPartyDomains
        } else {
            assertionFailure("\(Self.className) does not respond to \(Self.thirdPartyDomainsKey)")
        }

        output = result
        return true
    }

    public static func _forceBridgeFromObjectiveC(_ source: AnyObject, result: inout CustomHeaderFields?) {
        _=_conditionallyBridgeFromObjectiveC(source, result: &result)
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: AnyObject?) -> CustomHeaderFields {
        var result: CustomHeaderFields!
        _=_conditionallyBridgeFromObjectiveC(source!, result: &result)
        return result
    }

    // swiftlint:enable identifier_name

}
#endif
