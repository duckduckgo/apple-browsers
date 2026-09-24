//
//  RedesignedNewTabPageEscapeHatchView.swift
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

import SwiftUI

/// Renders the same eligible return-to-tab model as the production resting page.
struct RedesignedNewTabPageEscapeHatchView: View {
    @ObservedObject var pageModel: NewTabPageViewModel

    var body: some View {
        if let escapeHatch = pageModel.escapeHatch {
            EscapeHatchView(model: escapeHatch)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.top, Metrics.topPadding)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum Metrics {
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 20
}
