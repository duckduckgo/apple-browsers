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

enum SlideToDeleteStyle: String, CaseIterable, Identifiable {
    static let preferenceKey = "slideToDeleteStyle"

    case original
    case glass

    var id: String { rawValue }
    var title: String { self == .original ? "Original" : "Glass" }

    static var isGlassAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static let defaultValue: Self = .original

    func resolved(isGlassAvailable: Bool) -> Self {
        self == .glass && !isGlassAvailable ? .original : self
    }
}

enum SlideToDeleteVariant: String, CaseIterable, Identifiable {
    static let preferenceKey = "slideToDeleteVariant"
    static let defaultValue: Self = .shimmer

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
    var variant: SlideToDeleteVariant = .defaultValue
    var style: SlideToDeleteStyle = .defaultValue
    var onHapticRequest: () -> Void = { }
    var onTouchHapticRequest: () -> Void = { }
    var onCompletionLabelReveal: () -> Void = { }
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var layoutDirection
    @GestureState private var gestureIsActive = false
    @State private var translation: CGFloat = 0
    @State private var isDragging = false
    @State private var isThumbExpanded = false
    @State private var returnID = 0
    @State private var state = SlideToDeleteState()
    @StateObject private var feedback = SlideToDeleteFeedback()

    private let minimumHeight: CGFloat = 60
    private let handleInset: CGFloat = 3
    private var effectiveStyle: SlideToDeleteStyle { style.resolved(isGlassAvailable: SlideToDeleteStyle.isGlassAvailable) }
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
            .background {
                GeometryReader { geometry in
                    track(size: geometry.size)
                }
            }
            .overlay {
                GeometryReader { geometry in
                    slider(size: geometry.size)
                }
            }
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
            .task(id: returnID) {
                guard !isDragging, !state.isComplete else { return }
                if !reduceMotion {
                    do {
                        try await Task.sleep(nanoseconds: 160_000_000)
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.8)) {
                    isThumbExpanded = false
                }
            }
            .onChange(of: gestureIsActive) { active in
                if !active && isDragging { cancelDrag() }
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active { cancelDrag() }
            }
            .onAppear { feedback.prepare() }
            .onDisappear { cancelDrag() }
    }

    private func track(size: CGSize) -> some View {
        let travel = max(size.width - size.height, 0)
        let progress = state.isComplete ? 1 : state.progress(translation: translation, travel: travel)
        let showsCompletion = progress >= SlideToDeleteState.completionThreshold
        let fillHeight = max(size.height - handleInset * 2, 0)
        let fillWidth = fillHeight + progress * travel
        return ZStack {
            Capsule()
                .fill(Color(designSystemColor: .controlsFillPrimary))
            Color(designSystemColor: .destructivePrimary)
                .overlay {
                    if variant == .shimmer {
                        LinearGradient(stops: [
                            .init(color: Color(designSystemColor: .destructivePrimary), location: 0),
                            .init(color: Color(designSystemColor: .destructivePrimary), location: 0.5),
                            .init(color: Color(singleUseColor: .fireModeAccent), location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                            .opacity(min(max((progress - 0.6) / 0.4, 0), 1))
                    }
                }
                .frame(width: fillWidth, height: fillHeight)
                .clipShape(Capsule())
                .frame(width: max(size.width - handleInset * 2, 0), alignment: .leading)
                .padding(handleInset)
                .opacity(progress > 0 ? 1 : 0)
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
                .foregroundColor(Color(designSystemColor: .destructivePrimary))
                .padding(.horizontal, max(minimumHeight + 8, size.height))
                .frame(width: size.width, height: size.height)
                .opacity(showsCompletion ? 0 : 1)
            SlideToDeleteCompletionEffect(variant: variant,
                                          isActive: showsCompletion,
                                          showCompletionLabel: isDragging && state.shouldShowCompletionLabel)
                .padding(handleInset)
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .animation(reduceMotion || isDragging ? nil : .easeOut(duration: 0.16), value: translation)
    }

    private func slider(size: CGSize) -> some View {
        let inset = isThumbExpanded || state.isComplete ? 0 : handleInset
        let diameter = max(size.height - inset * 2, 0)
        let travel = max(size.width - size.height, 0)
        let progress = state.isComplete ? 1 : state.progress(translation: translation, travel: travel)
        return thumb(diameter: diameter)
            .contentShape(Circle().inset(by: -diameter * 0.05))
            .opacity(state.isComplete ? 0 : 1)
            .offset(x: direction * progress * travel)
            .gesture(dragGesture(travel: travel))
            .frame(width: size.width - inset * 2, height: diameter, alignment: .leading)
            .padding(inset)
            .animation(reduceMotion || isDragging ? nil : .easeOut(duration: 0.16), value: translation)
    }

    @ViewBuilder private func thumb(diameter: CGFloat) -> some View {
        let label = Image(uiImage: layoutDirection == .rightToLeft
                          ? DesignSystemImages.Glyphs.Size24.chevronLeftSmall
                          : DesignSystemImages.Glyphs.Size24.chevronRightSmall)
            .foregroundColor(Color(designSystemColor: effectiveStyle == .glass ? .textPrimary : .destructivePrimary))
            .frame(width: diameter, height: diameter)
        if #available(iOS 26.0, *), effectiveStyle == .glass, !reduceTransparency {
            label.glassEffect(.regular, in: Circle())
        } else {
            label
                .background(Color(designSystemColor: .controlsRaisedFillPrimary), in: Circle())
                .overlay { Circle().strokeBorder(Color(designSystemColor: .shadowPrimary), lineWidth: 0.5) }
                .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 3, y: 2)
                .shadow(color: Color(designSystemColor: .shadowPrimary), radius: 1, y: 1)
        }
    }

    private func dragGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureIsActive) { _, active, _ in active = true }
            .onChanged { value in
                guard !state.isComplete else { return }
                if !isDragging {
                    isDragging = true
                    returnID += 1
                    withAnimation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.75)) {
                        isThumbExpanded = true
                    }
                    if feedback.beginTouch() { onTouchHapticRequest() }
                }
                translation = direction * value.translation.width
                if state.updateDrag(translation: translation, travel: travel) { requestHaptic() }
            }
            .onEnded { value in
                feedback.endTouch()
                if state.endDrag(translation: direction * value.translation.width, travel: travel) { requestHaptic() }
                isDragging = false
                returnID += 1
                if !state.isComplete {
                    translation = 0
                }
            }
    }

    private func cancelDrag() {
        feedback.endTouch()
        isDragging = false
        returnID += 1
        state.resetDrag()
        translation = 0
    }

    private func requestHaptic() {
        if feedback.impact() {
            onHapticRequest()
        }
    }

}
