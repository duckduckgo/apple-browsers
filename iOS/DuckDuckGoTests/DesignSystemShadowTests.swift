//
//  DesignSystemShadowTests.swift
//  DuckDuckGo
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

import DesignResourcesKit
import UIKit
import XCTest

final class DesignSystemShadowTests: XCTestCase {

    func testCardStyleIsSingleSecondaryShadowWithRadius12AndOffset4() {
        XCTAssertEqual(DesignSystemShadowStyle.card.layers, [
            DesignSystemShadowLayer(color: .shadowSecondary, opacity: 1, radius: 12, x: 0, y: 4)
        ])
    }

    func testSearchFieldStyleIsSingleSecondaryShadowWithRadius12AndOffset8() {
        XCTAssertEqual(DesignSystemShadowStyle.searchField.layers, [
            DesignSystemShadowLayer(color: .shadowSecondary, opacity: 1, radius: 12, x: 0, y: 8)
        ])
    }

    func testWhenApplyingCardStyleToLayerThenShadowPropertiesMatchTheStyle() {
        let layer = CALayer()
        let traits = UITraitCollection(userInterfaceStyle: .light)

        layer.applyDesignSystemShadow(.card, traitCollection: traits)

        XCTAssertEqual(layer.shadowOpacity, 1)
        XCTAssertEqual(layer.shadowRadius, 12)
        XCTAssertEqual(layer.shadowOffset, CGSize(width: 0, height: 4))
        XCTAssertEqual(layer.shadowColor, UIColor(designSystemColor: .shadowSecondary).resolvedColor(with: traits).cgColor)
    }

    func testWhenApplyingStyleInDarkModeThenShadowColorIsResolvedForDarkMode() {
        let layer = CALayer()
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let darkColor = UIColor(designSystemColor: .shadowSecondary).resolvedColor(with: dark).cgColor

        layer.applyDesignSystemShadow(.searchField, traitCollection: dark)

        XCTAssertEqual(layer.shadowColor, darkColor)
        XCTAssertNotEqual(layer.shadowColor, UIColor(designSystemColor: .shadowSecondary).resolvedColor(with: light).cgColor)
        XCTAssertEqual(layer.shadowOffset, CGSize(width: 0, height: 8))
    }
}
