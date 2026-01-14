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
import DesignResourcesKit

struct WarnBeforeQuitView: View {

    @ObservedObject var viewModel: WarnBeforeQuitViewModel

    var body: some View {
        HStack(spacing: 48) {
            // Circular progress indicator
            ZStack {
                // Background circle
                Circle()
                    .fill(Color(designSystemColor: .controlsFillPrimary))
                    .frame(width: 52, height: 52)

                // Progress arc
                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(
                        Color(designSystemColor: .accentPrimary),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.05), value: viewModel.progress)

                // Shortcut text (⌘Q or ⌘W)
                Text(verbatim: viewModel.action.shortcutText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }

            // Text content
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.action.actionText)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                if let subtitle = viewModel.subtitleText {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
            }

            Spacer()

            // "Don't Show Again" button
            Text(UserText.confirmDontShowAgain)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(designSystemColor: .controlsFillPrimary))
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
        .padding(.top, 24)
        .padding(.bottom, 24)
        .padding(.leading, 32)
        .padding(.trailing, 32)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(Color(designSystemColor: .surfaceTertiary))
        )
        .shadow(color: Color(designSystemColor: .shadowPrimary), radius: 40, x: 0, y: 20)
        .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 12, x: 0, y: 4)
        .frame(width: 550, height: 100)
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
