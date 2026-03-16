//
//  NavigationBarStyleProviding.swift
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

import AppKit

protocol NavigationBarStyleProviding {
    var topCornerRadius: CGFloat? { get }
}

final class DefaultNavigationBarStyleProviding: NavigationBarStyleProviding {
    let topCornerRadius: CGFloat? = 10
}

final class RefreshNavigationBarStyleProviding: NavigationBarStyleProviding {
    let topCornerRadius: CGFloat? = 12
}

struct NavigationBarStyleProvidingFactory {

    static func buildStyleProvider(displaysTabsAnimations: Bool) -> NavigationBarStyleProviding {
        if displaysTabsAnimations {
            return RefreshNavigationBarStyleProviding()
        }

        return DefaultNavigationBarStyleProviding()
    }
}
