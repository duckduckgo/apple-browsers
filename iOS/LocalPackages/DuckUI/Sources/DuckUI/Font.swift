//
//  Font.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import UIKit

extension UIFont {

    public static func appFont(ofSize size: CGFloat) -> UIFont {
        return UIFont.systemFont(ofSize: size)
    }

    public static func lightAppFont(ofSize size: CGFloat) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: UIFont.Weight.light)
    }

    public static func semiBoldAppFont(ofSize size: CGFloat) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: UIFont.Weight.semibold)
    }

    public static func boldAppFont(ofSize size: CGFloat) -> UIFont {
        return UIFont.boldSystemFont(ofSize: size)
    }
}

// MARK: - Previews

#if DEBUG
import SwiftUI

private struct AppFontGallery: View {
    private let sampleSizes: [CGFloat] = [13, 15, 17, 22]
    private let sample = "DuckDuckGo — The quick brown fox jumps over the lazy dog 0123456789"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("UIFont.lightAppFont(ofSize:)") { size in
                    UIFont.lightAppFont(ofSize: size)
                }
                section("UIFont.appFont(ofSize:)") { size in
                    UIFont.appFont(ofSize: size)
                }
                section("UIFont.semiBoldAppFont(ofSize:)") { size in
                    UIFont.semiBoldAppFont(ofSize: size)
                }
                section("UIFont.boldAppFont(ofSize:)") { size in
                    UIFont.boldAppFont(ofSize: size)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func section(_ title: String, font: @escaping (CGFloat) -> UIFont) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            ForEach(sampleSizes, id: \.self) { size in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(Int(size))pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Text(sample)
                        .font(Font(uiFont: font(size)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

#Preview("Fonts / Light") {
    AppFontGallery()
        .preferredColorScheme(.light)
}

#Preview("Fonts / Dark") {
    AppFontGallery()
        .preferredColorScheme(.dark)
}

#endif
