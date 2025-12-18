//
//  SystemPermissionWarningView.swift
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
import SwiftUI

/// A view displaying a warning about disabled system permissions with a clickable link.
/// Used in both the permission authorization popover and permission center.
struct SystemPermissionWarningView: View {

    let prefixText: String
    let linkText: String
    let linkColor: Color
    let action: () -> Void

    init(
        prefixText: String,
        linkText: String,
        linkColor: Color = Color(designSystemColor: .textLink),
        action: @escaping () -> Void
    ) {
        self.prefixText = prefixText
        self.linkText = linkText
        self.linkColor = linkColor
        self.action = action
    }

    var body: some View {
        (Text(prefixText)
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .textSecondary))
        + Text(" ")
        + Text(linkText)
            .font(.system(size: 12))
            .foregroundColor(linkColor))
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cursor(.pointingHand)
            .onTapGesture {
                action()
            }
    }
}
