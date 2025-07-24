//
//  TabBarView.swift
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

import AppKit

final class TabBarView: MouseOverView {

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityIdentifier() -> String {
        return "Tabs"
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .group
    }

    override func accessibilityTitle() -> String? {
        "Tab Bar"
    }

    override func accessibilityRoleDescription() -> String? {
        "Tab Bar"
    }

    override func accessibilityChildren() -> [Any]? {
        var result: [Any] = []
        for subview in self.subviews where subview.isVisible {
            if subview.isAccessibilityElement() {
                result.append(subview)
            } else {
                result.append(contentsOf: subview.accessibilityChildren() ?? [])
            }
        }
        return result
    }

}
