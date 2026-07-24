//
//  DesignResourcesKitTests.swift
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
import XCTest

final class DesignResourcesKitTests: XCTestCase {
    func testWhenCurrentPaletteIsChangedThenTheNewPaletteIsReturned() {
        let originalPalette = DesignSystemPalette.current
        defer {
            DesignSystemPalette.current = originalPalette
        }

#if os(iOS)
        DesignSystemPalette.current = .rebranded
        guard case .rebranded = DesignSystemPalette.current else {
            XCTFail("Expected the rebranded palette")
            return
        }
#elseif os(macOS)
        DesignSystemPalette.current = .green
        guard case .green = DesignSystemPalette.current else {
            XCTFail("Expected the green palette")
            return
        }
#endif
    }
}
