//
//  BrowsingMenuCloseButtonStyle.swift
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

struct BrowsingMenuCloseButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Color(designSystemColor: .iconsSecondary))
            .padding(Constant.padding)
            .background(backgroundColor(configuration.isPressed))
            .clipShape(Circle())
            .padding(Constant.padding)
            .contentShape(Circle()) // Makes whole button area tappable, when there's no background
    }
    
    private func backgroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(designSystemColor: .controlsFillTertiary) : Color(designSystemColor: .controlsFillPrimary)
    }

    struct Constant {
        static let padding: CGFloat = 4
    }
}
