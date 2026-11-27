//
//  SyncPairingURLInstruction.swift
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
import UIComponents

struct SyncPairingURLInstruction: View {
    static let pairingURL = "duck.com/pair"

    let format: String
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var fontSize: CGFloat = 15

    var body: some View {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        Text(format, replacing: "%@", with: pill(font: font).withBaselineOffset(font.descender - 4))
            .font(.subheadline)
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(verbatim: String(format: format, Self.pairingURL)))
    }

    private func pill(font: UIFont) -> UIImage {
        let text = NSAttributedString(string: Self.pairingURL, attributes: [
            .font: font,
            .foregroundColor: UIColor(designSystemColor: .textPrimary)
        ])
        let size = CGSize(width: ceil(text.size().width) + 12, height: ceil(font.lineHeight) + 8)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light).performAsCurrent {
                UIColor(designSystemColor: .decorationTertiary).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8).fill()
                text.draw(at: CGPoint(x: 6, y: 4))
            }
        }
    }
}
