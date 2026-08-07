//
//  StatusIndicatorView.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

/// The state a `StatusIndicatorView` reflects. Drives only the dot colour; the accompanying
/// label text is supplied by the caller so each feature keeps its own localized copy.
public enum StatusIndicator: Equatable {
    case alwaysOn
    case on
    case off
}

/// A small on/off status pill: a coloured dot plus a caller-supplied label. Green when on
/// (or always-on), muted when off. Callers pass `text` so the copy stays in their own module.
public struct StatusIndicatorView: View {
    private let status: StatusIndicator
    private let text: String
    private let isDotHidden: Bool

    public init(status: StatusIndicator, text: String, isDotHidden: Bool = false) {
        self.status = status
        self.text = text
        self.isDotHidden = isDotHidden
    }

    public var body: some View {
        HStack(spacing: 6) {
            if !isDotHidden {
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundColor(colorForStatus(status))
                    .animation(.easeInOut(duration: 0.3), value: status)
            }

            Text(text)
                .daxBodyRegular()
                .lineLimit(1)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .animation(.easeInOut(duration: 0.3), value: status)
        }
    }

    private func colorForStatus(_ status: StatusIndicator) -> Color {
        switch status {
        case .on, .alwaysOn:
            return DesignSystemRebrand.isAppRebranded()
                ? Color(singleUseColor: .rebranding(.alertGreen))
                : Color(designSystemColor: .alertGreen)
        case .off:
            return Color(designSystemColor: .textSecondary).opacity(0.33)
        }
    }
}

#Preview {
    VStack {
        StatusIndicatorView(status: .on, text: "On")
        StatusIndicatorView(status: .off, text: "Off")
        StatusIndicatorView(status: .alwaysOn, text: "Always On")
        StatusIndicatorView(status: .on, text: "On", isDotHidden: true)
        StatusIndicatorView(status: .off, text: "Off", isDotHidden: true)
    }
}

#endif
