//
//  SyncInstructionText.swift
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
import SwiftUI

struct SyncInstructionText: View {

    let markdown: String

    var body: some View {
        Text(attributed)
            .daxSubheadRegular()
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        result.foregroundColor = Color(designSystemColor: .textSecondary)
        let emphasizedRanges = result.runs
            .filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map(\.range)
        for range in emphasizedRanges {
            result[range].foregroundColor = Color(designSystemColor: .textPrimary)
            result[range].inlinePresentationIntent = nil
        }
        return result
    }
}
