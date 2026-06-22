//
//  WKUserContentController+TestObservers.swift
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
import ObjectiveC.runtime
import WebKit

extension WKUserContentController {

    private static let contentRuleListsKey = UnsafeRawPointer(bitPattern: "DBPContentRuleListsKey".hashValue)!

    /// Test-only mirror of which `WKContentRuleList`s have been installed on this controller.
    /// Populated by the swizzled `addContentRuleList:` / `removeContentRuleList:` /
    /// `removeAllContentRuleLists` once `swizzleContentRuleListsMethodsOnce` has run.
    public var installedContentRuleLists: [WKContentRuleList] {
        get {
            objc_getAssociatedObject(self, Self.contentRuleListsKey) as? [WKContentRuleList] ?? []
        }
        set {
            objc_setAssociatedObject(self, Self.contentRuleListsKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    /// Swizzles `WKUserContentController`'s rule-list methods so installs/removals
    /// are mirrored into `installedContentRuleLists`. Idempotent — read it from a test
    /// `setUp` to ensure it's installed before any rule-list mutation runs.
    public static var swizzleContentRuleListsMethodsOnce: Void = {
        let originalAddMethod = class_getInstanceMethod(WKUserContentController.self, NSSelectorFromString("addContentRuleList:"))!
        let swizzledAddMethod = class_getInstanceMethod(WKUserContentController.self, #selector(swizzled_addContentRuleList))!
        method_exchangeImplementations(originalAddMethod, swizzledAddMethod)

        let originalRemoveMethod = class_getInstanceMethod(WKUserContentController.self, NSSelectorFromString("removeContentRuleList:"))!
        let swizzledRemoveMethod = class_getInstanceMethod(WKUserContentController.self, #selector(swizzled_removeContentRuleList))!
        method_exchangeImplementations(originalRemoveMethod, swizzledRemoveMethod)

        let originalRemoveAllMethod = class_getInstanceMethod(WKUserContentController.self, #selector(removeAllContentRuleLists))!
        let swizzledRemoveAllMethod = class_getInstanceMethod(WKUserContentController.self, #selector(swizzled_removeAllContentRuleLists))!
        method_exchangeImplementations(originalRemoveAllMethod, swizzledRemoveAllMethod)
    }()

    @objc dynamic private func swizzled_addContentRuleList(_ contentRuleList: WKContentRuleList) {
        installedContentRuleLists.append(contentRuleList)
        self.swizzled_addContentRuleList(contentRuleList) // call the original
    }

    @objc dynamic private func swizzled_removeContentRuleList(_ contentRuleList: WKContentRuleList) {
        if let index = installedContentRuleLists.firstIndex(of: contentRuleList) {
            installedContentRuleLists.remove(at: index)
        }
        self.swizzled_removeContentRuleList(contentRuleList) // call the original
    }

    @objc dynamic private func swizzled_removeAllContentRuleLists() {
        installedContentRuleLists.removeAll()
        self.swizzled_removeAllContentRuleLists() // call the original
    }
}
