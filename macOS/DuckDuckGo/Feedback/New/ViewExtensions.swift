//
//  ViewExtensions.swift
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

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}

extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }

    func systemLabel(color: Color = .textPrimary) -> some View {
        self
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(color)
    }

    func systemTitle2(color: Color = .textPrimary) -> some View {
        self
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(color)
    }

    func caption2(color: Color = .textSecondary) -> some View {
        self
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(color)
    }

    func body(color: Color = .textPrimary) -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
    }
}
