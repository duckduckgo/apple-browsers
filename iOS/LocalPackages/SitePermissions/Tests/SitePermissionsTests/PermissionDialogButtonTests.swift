//
//  PermissionDialogButtonTests.swift
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

import DesignResourcesKitIcons
import DuckUI
import SwiftUI
import XCTest
@testable import SitePermissions

@MainActor
final class PermissionDialogButtonTests: XCTestCase {

    func testDialogButtonsHave48PointDefaultHeightAndGrowForLargerText() {
        let originalRebrand = AppRebrand.isAppRebranded
        defer { AppRebrand.isAppRebranded = originalRebrand }

        for isRebranded in [false, true] {
            AppRebrand.isAppRebranded = { isRebranded }
            for colorScheme in [ColorScheme.light, .dark] {
                let button = Button {} label: {
                    PermissionDialogButtonLabel(title: "Change Permissions")
                }
                .environment(\.colorScheme, colorScheme)
                assertDialogHeight(of: button.buttonStyle(PrimaryButtonStyle(isFreeform: true)))
                assertDialogHeight(of: button.buttonStyle(SecondaryFillButtonStyle(isFreeform: true)))

                // Existing callers retain the shared styles' larger default layout.
                let ordinaryButton = Button {} label: { Text("Change Permissions").font(.body.weight(.medium)) }
                XCTAssertGreaterThanOrEqual(height(of: ordinaryButton.buttonStyle(PrimaryButtonStyle()).dynamicTypeSize(.large)), 50)
                XCTAssertGreaterThanOrEqual(height(of: ordinaryButton.buttonStyle(SecondaryFillButtonStyle()).dynamicTypeSize(.large)), 50)
            }
        }
    }

    private func assertDialogHeight(of view: some View, file: StaticString = #filePath, line: UInt = #line) {
        let standardHeight = height(of: view.environment(\.dynamicTypeSize, .large))
        let accessibleHeight = height(of: view.environment(\.dynamicTypeSize, .accessibility3))
        XCTAssertEqual(standardHeight, 48, accuracy: 0.5, file: file, line: line)
        XCTAssertGreaterThan(accessibleHeight, standardHeight, file: file, line: line)
    }

    private func height(of view: some View) -> CGFloat {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: 260, height: 1000)).height
    }
}
