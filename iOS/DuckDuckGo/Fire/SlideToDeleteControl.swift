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
    private(set) var isAtCompletionThreshold = false
    private(set) var thresholdEntryCount = 0
    private(set) var shouldShowCompletionLabel = false

    func progress(translation: CGFloat, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        return min(max(translation / travel, 0), 1)
    }

    mutating func updateDrag(translation: CGFloat, travel: CGFloat) -> Bool {
        guard !isComplete else { return false }
        let wasAtCompletionThreshold = isAtCompletionThreshold
        isAtCompletionThreshold = progress(translation: translation, travel: travel) >= Self.completionThreshold
        if !isAtCompletionThreshold {
            shouldShowCompletionLabel = false
        }
        let didEnterThreshold = isAtCompletionThreshold && !wasAtCompletionThreshold
        if didEnterThreshold {
            thresholdEntryCount += 1
        }
        return didEnterThreshold
    }

    mutating func resetDrag() {
        isAtCompletionThreshold = false
        shouldShowCompletionLabel = false
    }

    mutating func complete(translation: CGFloat, travel: CGFloat) -> Bool {
        guard !isComplete, progress(translation: translation, travel: travel) >= Self.completionThreshold else { return false }
        isComplete = true
        shouldShowCompletionLabel = false
        return true
    }

    mutating func endDrag(translation: CGFloat, travel: CGFloat) -> Bool {
        let shouldProvideFeedback = updateDrag(translation: translation, travel: travel)
        _ = complete(translation: translation, travel: travel)
        resetDrag()
        return shouldProvideFeedback
    }

    @discardableResult
    mutating func revealCompletionLabel(for thresholdEntry: Int) -> Bool {
        guard !isComplete, isAtCompletionThreshold, thresholdEntry == thresholdEntryCount,
              !shouldShowCompletionLabel else { return false }
        shouldShowCompletionLabel = true
        return true
    }
}

enum SlideToDeleteVariant: String, CaseIterable, Identifiable {
    static let preferenceKey = "slideToDeleteVariant"

    case basic
    case flameBurst
    case fireSweep
    case shimmer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "Basic"
        case .flameBurst: return "Flame Burst"
        case .fireSweep: return "Fire Sweep"
        case .shimmer: return "Shimmer"
        }
    }
}

struct SlideToDeleteControl: View {
    let title: String
    var variant: SlideToDeleteVariant = .basic
    var onHapticRequest: () -> Void = { }
    var onCompletionLabelReveal: () -> Void = { }
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.8))) private var translation: CGFloat = 0
    @GestureState private var isDragging = false
    @State private var state = SlideToDeleteState()
    @StateObject private var feedback = SlideToDeleteFeedback()

    private let minimumHeight: CGFloat = 50
    private let handleInset: CGFloat = 4
    private var direction: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }
    private var completionHoldID: Int? {
        variant == .shimmer && isDragging && state.isAtCompletionThreshold && !state.isComplete ? state.thresholdEntryCount : nil
    }

    var body: some View {
        // Keep height when label shrinks.
        Text(" ")
            .font(.body.weight(.medium))
            .padding(.vertical)
            .frame(maxWidth: .infinity, minHeight: minimumHeight)
            .background(Color(designSystemColor: .controlsFillPrimary), in: Capsule())
            .overlay {
                GeometryReader { geometry in
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .allowsTightening(true)
                        .foregroundColor(Color(designSystemColor: .destructivePrimary))
                        .padding(.horizontal, max(minimumHeight + 8, geometry.size.height))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .overlay {
                GeometryReader { geometry in
                    let inset = isDragging || state.isComplete ? 0 : handleInset
                    let diameter = max(geometry.size.height - inset * 2, 0)
                    let travel = max(geometry.size.width - geometry.size.height, 0)
                    let progress = state.isComplete ? 1 : state.progress(translation: translation, travel: travel)
                    let offset = progress * travel
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(fillColor(progress: progress))
                            .frame(width: diameter + offset, height: diameter)
                            .overlay {
                                if variant == .shimmer {
                                    LinearGradient(colors: [Color(designSystemColor: .destructivePrimary), Color(singleUseColor: .fireModeAccent)],
                                                   startPoint: .leading, endPoint: .trailing)
                                        .opacity(min(max((progress - 0.35) / 0.45, 0), 1))
                                }
                            }
                            .overlay {
                                SlideToDeleteCompletionEffect(variant: variant,
                                                              isActive: progress >= SlideToDeleteState.completionThreshold,
                                                              showCompletionLabel: isDragging && state.shouldShowCompletionLabel)
                            }
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color(designSystemColor: .shadowPrimary), lineWidth: 0.5)
                            }
                            .overlay {
                                Capsule()
                                    .inset(by: 0.5)
                                    .stroke(Color(designSystemColor: .highlightDecoration), lineWidth: 1)
                                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                            }
                            .clipShape(Capsule())
                            .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 3, y: 2)
                            .shadow(color: Color(designSystemColor: .shadowPrimary), radius: 1, y: 1)
                            .allowsHitTesting(false)
                        Image(uiImage: layoutDirection == .rightToLeft
                              ? DesignSystemImages.Glyphs.Size24.chevronLeftSmall
                              : DesignSystemImages.Glyphs.Size24.chevronRightSmall)
                            .foregroundColor(Color(designSystemColor: colorScheme == .dark || progress > 0
                                                   ? .destructiveContentPrimary : .destructivePrimary))
                            .opacity(progress >= SlideToDeleteState.completionThreshold ? 0 : 1)
                            .frame(width: diameter, height: diameter)
                            .contentShape(Capsule())
                            .offset(x: direction * offset)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .updating($translation) { value, translation, _ in
                                        translation = direction * value.translation.width
                                    }
                                    .updating($isDragging) { _, isDragging, _ in
                                        isDragging = true
                                    }
                                    .onChanged { value in
                                        if state.updateDrag(translation: direction * value.translation.width, travel: travel) {
                                            requestHaptic()
                                        }
                                    }
                                    .onEnded { value in
                                        withAnimation(nil) {
                                            if state.endDrag(translation: direction * value.translation.width, travel: travel) {
                                                requestHaptic()
                                            }
                                        }
                                    }
                            )
                    }
                    .frame(width: geometry.size.width - inset * 2, height: diameter, alignment: .leading)
                    .padding(inset)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragging)
                }
            }
            .clipShape(Capsule())
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .background(SlideToDeleteFeedbackView(feedback: feedback))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                _ = state.complete(translation: 1, travel: 1)
            }
            .disabled(state.isComplete)
            .task(id: state.isComplete) {
                guard state.isComplete else { return }
                if (variant == .flameBurst || variant == .fireSweep) && !reduceMotion {
                    do {
                        try await Task.sleep(nanoseconds: 650_000_000)
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                action()
            }
            .task(id: completionHoldID) {
                guard let thresholdEntry = completionHoldID else { return }
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    if state.revealCompletionLabel(for: thresholdEntry) {
                        onCompletionLabelReveal()
                    }
                }
            }
            .onChange(of: isDragging) { isDragging in
                if isDragging {
                    feedback.prepare()
                } else {
                    state.resetDrag()
                }
            }
    }

    private func requestHaptic() {
        if feedback.impact() {
            onHapticRequest()
        }
    }

    private func fillColor(progress: CGFloat) -> Color {
        Color(designSystemColor: colorScheme == .dark || progress > 0 ? .destructivePrimary : .controlsRaisedFillPrimary)
    }
}

@MainActor
final class SlideToDeleteFeedback: ObservableObject {
    private var generator: UIImpactFeedbackGenerator?

    func attach(to view: UIView) {
        if #available(iOS 17.5, *) {
            generator = UIImpactFeedbackGenerator(style: .medium, view: view)
        } else {
            generator = UIImpactFeedbackGenerator(style: .medium)
        }
    }

    func prepare() {
        generator?.prepare()
    }

    @discardableResult
    func impact() -> Bool {
        guard let generator else { return false }
        generator.impactOccurred()
        return true
    }
}

struct SlideToDeleteFeedbackView: UIViewRepresentable {
    let feedback: SlideToDeleteFeedback

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isAccessibilityElement = false
        feedback.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { }
}
