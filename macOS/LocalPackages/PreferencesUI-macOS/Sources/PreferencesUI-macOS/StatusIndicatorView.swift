//
//  StatusIndicatorView.swift
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

import SwiftUI
import DesignResourcesKit

public enum StatusIndicator: Equatable {
    case alwaysOn
    case on
    case off
    case custom(String)

    var text: String {
        switch self {
        case .alwaysOn:
            return UserText.preferencesAlwaysOn
        case .on:
            return UserText.preferencesOn
        case .off:
            return UserText.preferencesOff
        case .custom(let customText):
            return customText
        }
    }
}

public struct StatusIndicatorView: View {
    var status: StatusIndicator
    var isLarge: Bool = false

    private var fontSize: CGFloat {
        isLarge ? 13 : 10
    }

    private var circleSize: CGFloat {
        isLarge ? 7 : 5
    }

    public init(status: StatusIndicator, isLarge: Bool = false) {
        self.status = status
        self.isLarge = isLarge
    }

    public var body: some View {
        HStack(spacing: isLarge ? 6 : 4) {
            Circle()
                .frame(width: circleSize, height: circleSize)
                .foregroundColor(colorForStatus(status))

            Text(status.text)
                .font(.system(size: fontSize))
                .foregroundColor(.secondary)
        }
    }

    private func colorForStatus(_ status: StatusIndicator) -> Color {
        switch status {
        case .on, .alwaysOn:
            return Color(designSystemColor: .alertGreen)
        case .off:
            return Color.secondary.opacity(0.33)
        case .custom:
            return .orange
        }
    }
}
