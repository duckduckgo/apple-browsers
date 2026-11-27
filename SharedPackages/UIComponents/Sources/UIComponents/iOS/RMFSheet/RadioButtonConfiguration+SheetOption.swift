//
//  RadioButtonConfiguration+SheetOption.swift
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

#if os(iOS)

import SwiftUI
import DesignResourcesKit

public extension RadioButtonConfiguration {

    /// The RMF sheet's option row (Figma `.Sheet part / Option`): a label, an optional description
    /// (the item's `secondaryText`) and a trailing radio, on a 24pt rounded surface.
    ///
    /// Selected rows get a 1.5pt accent border on an accent glow fill; unselected rows get a hairline
    /// container border.
    static var sheetOption: RadioButtonConfiguration {
        RadioButtonConfiguration(
            font: RMFSheetTypography.bodyRegular,
            selectedTextColor: Color(designSystemColor: .textPrimary),
            unselectedTextColor: Color(designSystemColor: .textPrimary),
            selectedBackgroundColor: Color(designSystemColor: .accentGlowSecondary),
            unselectedBackgroundColor: Color(designSystemColor: .surface),
            selectedBorderColor: Color(designSystemColor: .accentPrimary),
            unselectedBorderColor: Color(designSystemColor: .containerBorderPrimary),
            selectedCheckboxColor: Color(designSystemColor: .accentPrimary),
            selectedCheckboxBackgroundColor: Color(designSystemColor: .accentContentPrimary),
            unselectedCheckboxColor: Color(designSystemColor: .iconsTertiary),
            borderWidth: 1,
            cornerRadius: 24,
            horizontalPadding: 20,
            verticalPadding: 14,
            spacing: 12,
            checkboxSize: 24,
            layout: .vertical,
            buttonSpacing: 8,
            secondaryFont: RMFSheetTypography.subheadRegular,
            secondaryTextColor: Color(designSystemColor: .textSecondary),
            selectedBorderWidth: 1.5,
            indicatorStyle: .radio
        )
    }
}

#endif
