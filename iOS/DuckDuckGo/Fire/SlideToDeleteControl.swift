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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @GestureState private var gestureIsActive = false
    @State private var translation: CGFloat = 0
    @State private var isDragging = false
    @State private var isThumbExpanded = false
    @State private var hasSlid = false
    @State private var returnID = 0
    @State private var state = SlideToDeleteState()
    @StateObject private var feedback = SlideToDeleteFeedback()

    private let minimumHeight: CGFloat = 60
    private let handleInset: CGFloat = 4
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
                hasSlid = false
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

    private func slider(size: CGSize) -> some View {
        let inset = isThumbExpanded || state.isComplete ? 0 : handleInset
        let diameter = max(size.height - inset * 2, 0)
        let travel = max(size.width - size.height, 0)
        let progress = state.isComplete ? 1 : state.progress(translation: translation, travel: travel)
        let offset = progress * travel
        let isOriginal = effectiveStyle == .original
        let showsCompletion = progress >= SlideToDeleteState.completionThreshold
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(designSystemColor: isOriginal && colorScheme != .dark && !hasSlid && !state.isComplete
                            ? .controlsRaisedFillPrimary : .destructivePrimary))
                .frame(width: isOriginal ? diameter + offset : size.width - inset * 2, height: diameter)
                .overlay {
                    if variant == .shimmer {
                        LinearGradient(colors: [Color(designSystemColor: .destructivePrimary), Color(singleUseColor: .fireModeAccent)],
                                       startPoint: .leading, endPoint: .trailing)
                            .opacity(isOriginal ? min(max((progress - 0.35) / 0.45, 0), 1) : 1)
                    }
                }
                .overlay {
                    SlideToDeleteCompletionEffect(variant: variant,
                                                  isActive: showsCompletion,
                                                  showCompletionLabel: isDragging && state.shouldShowCompletionLabel)
                }
                .overlay {
                    if isOriginal {
                        Capsule().strokeBorder(Color(designSystemColor: .shadowPrimary), lineWidth: 0.5)
                    }
                }
                .overlay {
                    if isOriginal {
                        Capsule().inset(by: 0.5)
                            .stroke(Color(designSystemColor: .highlightDecoration), lineWidth: 1)
                            .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                    }
                }
                .clipShape(Capsule())
                .shadow(color: Color(designSystemColor: .shadowSecondary).opacity(isOriginal ? 1 : 0), radius: 3, y: 2)
                .shadow(color: Color(designSystemColor: .shadowPrimary).opacity(isOriginal ? 1 : 0), radius: 1, y: 1)
                .opacity(isOriginal || (showsCompletion && variant != .basic) ? 1 : 0)
                .allowsHitTesting(false)
            thumb(diameter: diameter)
                .contentShape(Circle().inset(by: -diameter * 0.05))
                .opacity(state.isComplete || (isOriginal && showsCompletion) ? 0 : 1)
                .offset(x: direction * offset)
                .gesture(dragGesture(travel: travel))
        }
        .frame(width: size.width - inset * 2, height: diameter, alignment: .leading)
        .padding(inset)
        .animation(reduceMotion || isDragging ? nil : .easeOut(duration: 0.16), value: translation)
    }

    @ViewBuilder private func thumb(diameter: CGFloat) -> some View {
        let label = Image(uiImage: layoutDirection == .rightToLeft
                          ? DesignSystemImages.Glyphs.Size24.chevronLeftSmall
                          : DesignSystemImages.Glyphs.Size24.chevronRightSmall)
            .foregroundColor(Color(designSystemColor: effectiveStyle == .glass ? .textPrimary
                                   : colorScheme == .dark || hasSlid ? .destructiveContentPrimary : .destructivePrimary))
            .frame(width: diameter, height: diameter)
        if effectiveStyle == .original {
            label
        } else if #available(iOS 26.0, *), !reduceTransparency {
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
                let progress = state.progress(translation: translation, travel: travel)
                if progress > 0 { hasSlid = true }
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
