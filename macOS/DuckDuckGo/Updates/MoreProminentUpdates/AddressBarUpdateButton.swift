//
//  AddressBarUpdateButton.swift
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

import AppKit
import DesignResourcesKit
import SwiftUI

/// Prominent update button shown in the navigation bar, to the left of the browser menu button.
struct AddressBarUpdateButton: View {

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .tracking(MoreProminentUpdatesTypography.titleTracking)
                .lineLimit(1)
        }
        .buttonStyle(AddressBarUpdateButtonStyle())
    }
}

private struct AddressBarUpdateButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        AddressBarUpdateButtonBody(configuration: configuration)
    }
}

private struct AddressBarUpdateButtonBody: View {

    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color(designSystemColor: .accentTertiary)
        }
        return Color(designSystemColor: isHovered ? .accentSecondary : .accentPrimary)
    }

    var body: some View {
        configuration.label
            .foregroundColor(Color(designSystemColor: .accentContentPrimary))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 9).fill(backgroundColor))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onHover { isHovered = $0 }
    }
}

extension AddressBarUpdateButton {

    /// Hosts the button at its fitting width, for use as an arranged subview of the navigation bar's stack view.
    func embeddedInHostingView() -> NSView {
        let hostingView = NSHostingView(rootView: self)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
        hostingView.setContentHuggingPriority(.required, for: .horizontal)
        return hostingView
    }
}

enum MoreProminentUpdatesTypography {
    /// The design's 13pt labels use -0.25pt letter spacing; the system font already applies about -0.08pt at that size.
    static let titleTracking: CGFloat = -0.17
}

#Preview {
    AddressBarUpdateButton(title: UserText.addressBarUpdateButton) {}
        .padding()
}
