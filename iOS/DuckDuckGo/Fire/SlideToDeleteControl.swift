//
//  SlideToDeleteControl.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons

struct SlideToDeleteState {
    static let completionThreshold: CGFloat = 0.95

    private(set) var isComplete = false
    private var hasProvidedFeedback = false

    func progress(translation: CGFloat, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        return min(max(translation / travel, 0), 1)
    }

    mutating func updateDrag(translation: CGFloat, travel: CGFloat) -> Bool {
        guard !isComplete, !hasProvidedFeedback,
              progress(translation: translation, travel: travel) >= Self.completionThreshold else { return false }
        hasProvidedFeedback = true
        return true
    }

    mutating func resetDrag() {
        hasProvidedFeedback = false
    }

    mutating func complete(translation: CGFloat, travel: CGFloat) -> Bool {
        guard !isComplete, progress(translation: translation, travel: travel) >= Self.completionThreshold else { return false }
        isComplete = true
        return true
    }
}

struct SlideToDeleteControl: View {
    let title: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.8))) private var translation: CGFloat = 0
    @GestureState private var isDragging = false
    @State private var state = SlideToDeleteState()
    @State private var feedback = UIImpactFeedbackGenerator(style: .medium)

    private let handleSize: CGFloat = 48
    private let handleInset: CGFloat = 4
    private var direction: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }

    var body: some View {
        Text(title)
            .font(.body.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundColor(Color(designSystemColor: .destructivePrimary))
            .padding(.horizontal, handleSize + 8)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: handleSize + handleInset * 2)
            .background(Color(designSystemColor: .controlsFillPrimary),
                        in: RoundedRectangle(cornerRadius: handleSize / 2 + handleInset, style: .continuous))
            .overlay {
                GeometryReader { geometry in
                    let travel = max(geometry.size.width - handleSize, 0)
                    let progress = state.isComplete ? 1 : state.progress(translation: translation, travel: travel)
                    let offset = progress * travel
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: handleSize / 2, style: .continuous)
                            .fill(fillColor(progress: progress))
                            .overlay {
                                RoundedRectangle(cornerRadius: handleSize / 2, style: .continuous)
                                    .strokeBorder(Color(designSystemColor: .shadowPrimary), lineWidth: 0.5)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: handleSize / 2, style: .continuous)
                                    .inset(by: 0.5)
                                    .stroke(Color(designSystemColor: .highlightDecoration), lineWidth: 1)
                                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                            }
                            .frame(width: handleSize + offset)
                            .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 3, y: 2)
                            .shadow(color: Color(designSystemColor: .shadowPrimary), radius: 1, y: 1)
                            .allowsHitTesting(false)
                        Image(uiImage: layoutDirection == .rightToLeft
                              ? DesignSystemImages.Glyphs.Size24.chevronLeftSmall
                              : DesignSystemImages.Glyphs.Size24.chevronRightSmall)
                            .foregroundColor(Color(designSystemColor: colorScheme == .dark ? .destructiveContentPrimary : .destructivePrimary))
                            .opacity(progress >= SlideToDeleteState.completionThreshold ? 0 : 1)
                            .frame(width: handleSize, height: geometry.size.height)
                            .contentShape(Capsule())
                            .offset(x: direction * offset)
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .updating($translation) { value, translation, _ in
                                        translation = direction * value.translation.width
                                    }
                                    .updating($isDragging) { _, isDragging, _ in
                                        isDragging = true
                                    }
                                    .onChanged { value in
                                        if state.updateDrag(translation: direction * value.translation.width, travel: travel) {
                                            feedback.impactOccurred()
                                        }
                                    }
                                    .onEnded { value in
                                        let didComplete = withAnimation(nil) {
                                            state.complete(translation: direction * value.translation.width, travel: travel)
                                        }
                                        if didComplete {
                                            action()
                                        }
                                    }
                            )
                    }
                }
                .padding(handleInset)
            }
            .clipShape(RoundedRectangle(cornerRadius: handleSize / 2 + handleInset, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard state.complete(translation: 1, travel: 1) else { return }
                action()
            }
            .disabled(state.isComplete)
            .onChange(of: isDragging) { isDragging in
                if isDragging {
                    feedback.prepare()
                } else {
                    state.resetDrag()
                }
            }
    }

    private func fillColor(progress: CGFloat) -> Color {
        Color(designSystemColor: colorScheme == .dark || progress >= SlideToDeleteState.completionThreshold ? .destructivePrimary : .controlsRaisedFillPrimary)
    }
}
