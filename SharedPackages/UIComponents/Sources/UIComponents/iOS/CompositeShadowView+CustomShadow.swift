//
//  CompositeShadowView+CustomShadow.swift
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

import DesignResourcesKit

#if os(iOS)
import UIKit

extension CompositeShadowView.Shadow {
    private static let defaultColor = UIColor(designSystemColor: .shadowPrimary)
    private static let focusColor = UIColor(designSystemColor: .shadowSecondary)

    static let defaultLayer1 = CompositeShadowView.Shadow(
        id: "ddg.shadow1",
        color: defaultColor,
        opacity: 1,
        radius: 12.0,
        offset: CGSize(width: 0, height: 4)
    )

    static let defaultLayer2 = CompositeShadowView.Shadow(
        id: "ddg.shadow2",
        color: defaultColor,
        opacity: 1,
        radius: 48.0,
        offset: CGSize(width: 0, height: 16)
    )

    static let activeLayer1 = CompositeShadowView.Shadow(
        id: "ddg.shadow1",
        color: focusColor,
        opacity: 1,
        radius: 12.0,
        offset: CGSize(width: 0, height: 2)
    )

    static let activeLayer2 = CompositeShadowView.Shadow(
        id: "ddg.shadow2",
        color: focusColor,
        opacity: 1,
        radius: 32.0,
        offset: CGSize(width: 0, height: 16)
    )
}

public extension CompositeShadowView {
    func applyDefaultShadow() {
        if shadows.isEmpty {
            shadows = [
                .defaultLayer1,
                .defaultLayer2
            ]
        } else {
            updateShadow(.defaultLayer1)
            updateShadow(.defaultLayer2)
        }
    }

    func applyActiveShadow() {
        if shadows.isEmpty {
            shadows = [
                .activeLayer1,
                .activeLayer2
            ]
        } else {
            updateShadow(.activeLayer1)
            updateShadow(.activeLayer2)
        }
    }

    static func defaultShadowView() -> Self {
        Self.init(shadows: [.defaultLayer1, .defaultLayer2])
    }
}
#endif
