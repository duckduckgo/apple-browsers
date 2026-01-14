//
//  WarnBeforeQuitView.swift
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

struct WarnBeforeQuitView: View {

    @ObservedObject var viewModel: WarnBeforeQuitViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Circular progress indicator
            ZStack {
                // Background circle
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 60, height: 60)

                // Progress arc
                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 54, height: 54)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.05), value: viewModel.progress)

                // Shortcut text (⌘Q or ⌘W)
                Text(verbatim: viewModel.action.shortcutText)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.action.actionText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                if let subtitle = viewModel.subtitleText {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            Spacer()

            // "Don‘t Show Again" button
            Text(UserText.confirmDontShowAgain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.1))
                        )
                )
                // Fires on mouseDown event to trigger the `onDontAskAgain` callback
                // before the popup is dismissed by the click event
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            viewModel.dontAskAgainTapped()
                        }
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
        )
        .frame(width: 520)
        .onHover { isHovering in
            viewModel.hoverChanged(isHovering)
        }
    }
}

#Preview {
    WarnBeforeQuitView(viewModel: WarnBeforeQuitViewModel())
        .padding(40)
        .background(Color.gray)
}
