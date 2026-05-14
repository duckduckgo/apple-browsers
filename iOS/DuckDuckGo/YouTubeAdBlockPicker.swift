//
//  YouTubeAdBlockPicker.swift
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
import UIKit
import DesignResourcesKit
import DesignResourcesKitIcons

enum YouTubeAdBlockMode: String, CaseIterable {
    case alwaysOn
    case disableUntilRelaunch
    case alwaysOff

    var title: String {
        switch self {
        case .alwaysOn: return UserText.youTubeAdBlockingModeAlwaysOn
        case .disableUntilRelaunch: return UserText.youTubeAdBlockingModeDisableUntilRelaunch
        case .alwaysOff: return UserText.youTubeAdBlockingModeAlwaysOff
        }
    }
}

struct YouTubeAdBlockPickerView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var selection: YouTubeAdBlockMode = .alwaysOn

    let onSelection: (YouTubeAdBlockMode) -> Void

    init(onSelection: @escaping (YouTubeAdBlockMode) -> Void = { _ in }) {
        self.onSelection = onSelection
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ForEach(Array(YouTubeAdBlockMode.allCases.enumerated()), id: \.element) { index, mode in
                row(for: mode)
                if index < YouTubeAdBlockMode.allCases.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color(designSystemColor: .backgroundTertiary))
    }

    private var header: some View {
        HStack {
            Text(UserText.youTubeAdBlockingPickerTitle)
                .font(.headline)
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
            }
            .buttonStyle(CloseButtonStyle())
            .accessibilityLabel(UserText.keyCommandClose)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    private func row(for mode: YouTubeAdBlockMode) -> some View {
        Button {
            selection = mode
            onSelection(mode)
        } label: {
            HStack(spacing: 16) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.check)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .opacity(mode == selection ? 1 : 0)
                Text(mode.title)
                    .font(.body)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
