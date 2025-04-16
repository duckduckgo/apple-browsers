//
//  DuckPlayerContainer.swift
//  DuckDuckGo
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

import Combine
import SwiftUI

public enum DuckPlayerContainer {
    public struct Constants {
        static let easeInOutDuration: Double = 0.3
        static let shortDuration: Double = 0.2
        static let springDuration: Double = 0.5
        static let springBounce: Double = 0.2
        static let initialOffsetValue: Double = 500.0
        static let dragThreshold: CGFloat = 50
        static let dragAreaHeight: CGFloat = 44
        static let contentTopPadding: CGFloat = 24
    }
    public struct PresentationMetrics {
        public let contentWidth: Double
    }

    @MainActor
    public final class ViewModel: ObservableObject {
        @Published public private(set) var sheetVisible = false
        @Published var sheetAnimationCompleted = false
        @Published var isDragging = false
        @Published private(set) var isKeyboardVisible = false

        private var originalSheetState = false // Add this to store the original state
        private var subscriptions = Set<AnyCancellable>()
        private var shouldAnimate = true

        public init() {
            observeKeyboard()
        }

        private func observeKeyboard() {
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self = self else { return }
                    let isVisible = notification.name == UIResponder.keyboardWillShowNotification

                    if isVisible {
                        self.originalSheetState = self.sheetVisible
                        self.isKeyboardVisible = true
                        self.dismiss()
                    } else {
                        self.isKeyboardVisible = false
                        if self.originalSheetState {
                            self.show()
                        }
                    }
                }
                .store(in: &subscriptions)
        }

        public var springAnimation: Animation? {
            shouldAnimate ? .spring(duration: 0.4, bounce: 0.5, blendDuration: 1.0) : nil
        }

        public func show() {
            sheetAnimationCompleted = false
            sheetVisible = true
        }

        public func dismiss() {
            sheetAnimationCompleted = false
            sheetVisible = false
        }

        public func setDragging(_ dragging: Bool) {
            isDragging = dragging
        }
    }

    public struct Container<Content: View>: View {
        @ObservedObject var viewModel: ViewModel
        @State private var sheetHeight = 0.0
        let hasBackground: Bool
        let content: (PresentationMetrics) -> Content
        let onDismiss: (Bool) -> Void
        let onPresentDuckPlayer: () -> Void

        public init(
            viewModel: ViewModel, hasBackground: Bool = true, onDismiss: @escaping (Bool) -> Void, onPresentDuckPlayer: @escaping () -> Void,
            @ViewBuilder content: @escaping (PresentationMetrics) -> Content
        ) {
            self.viewModel = viewModel
            self.hasBackground = hasBackground
            self.content = content
            self.onDismiss = onDismiss
            self.onPresentDuckPlayer = onPresentDuckPlayer
        }

        @ViewBuilder private func sheet(containerHeight: Double) -> some View {
            SheetView(
                viewModel: viewModel,
                containerHeight: containerHeight,
                content: content,
                onHeightChange: { sheetHeight = $0 },
                onDismiss: onDismiss,
                onPresentDuckPlayer: onPresentDuckPlayer
            )
        }

        public var body: some View {
            VStack(spacing: 0) {
                if hasBackground {
                    Color.black
                        .ignoresSafeArea()
                        .animation(viewModel.springAnimation, value: viewModel.sheetVisible)
                }

                // Use a fixed container height for offset calculations
                sheet(containerHeight: Constants.initialOffsetValue)
                    .frame(alignment: .bottom)
                    .opacity(viewModel.isKeyboardVisible ? 0 : 1)
            }
        }
    }
}

// MARK: - Private

private func calculateSheetOffset(for visible: Bool, containerHeight: Double) -> Double {
    visible ? 10 : containerHeight
}

@MainActor
private struct GrabHandle: View {
    struct Constants {
        static let grabHandleHeight: CGFloat = 4
        static let grabHandleWidth: CGFloat = 36
        static let grabHandleTopPadding: CGFloat = 4
        static let grabHandleBottomPadding: CGFloat = 8
    }

    var body: some View {
        Capsule()
            .fill(Color(designSystemColor: .textPrimary).opacity(0.3))
            .frame(width: Constants.grabHandleWidth, height: Constants.grabHandleHeight)
            .padding(.top, Constants.grabHandleTopPadding)
            .padding(.bottom, Constants.grabHandleBottomPadding)
    }
}

@MainActor
private struct SheetView<Content: View>: View {
    @ObservedObject var viewModel: DuckPlayerContainer.ViewModel
    let containerHeight: Double
    let content: (DuckPlayerContainer.PresentationMetrics) -> Content
    let onHeightChange: (Double) -> Void
    let onDismiss: (Bool) -> Void
    let onPresentDuckPlayer: () -> Void

    @State private var sheetHeight: Double = 0
    @State private var sheetWidth: Double?
    @State private var opacity: Double = 0
    @State private var sheetOffset = DuckPlayerContainer.Constants.initialOffsetValue
    @GestureState private var dragStartOffset: Double?
    @State private var isDragging = false

    // Animate the sheet offset with a spring animation
    private func animateOffset(to visible: Bool) {
        let offset = calculateSheetOffset(for: visible, containerHeight: containerHeight)
        if #available(iOS 17.0, *) {
            withAnimation(
                .spring(
                    duration: DuckPlayerContainer.Constants.springDuration, bounce: DuckPlayerContainer.Constants.springBounce)
            ) {
                sheetOffset = offset
            } completion: {
                viewModel.sheetAnimationCompleted = true
            }
        } else {
            withAnimation(
                .spring(
                    duration: DuckPlayerContainer.Constants.springDuration, bounce: DuckPlayerContainer.Constants.springBounce)
            ) {
                sheetOffset = offset
            }
            viewModel.sheetAnimationCompleted = true
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if let sheetWidth {
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        GrabHandle()

                        content(DuckPlayerContainer.PresentationMetrics(contentWidth: sheetWidth))
                            .padding(.top, DuckPlayerContainer.Constants.contentTopPadding)

                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: DuckPlayerContainer.Constants.dragAreaHeight)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .updating($dragStartOffset) { _, state, _ in
                                        if state == nil {
                                            state = sheetOffset
                                            viewModel.setDragging(true)
                                        }
                                    }
                                    .onChanged { value in
                                        guard let dragStartOffset else { return }

                                        let offsetY = value.translation.height
                                        if offsetY > 0 {
                                            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                                sheetOffset = dragStartOffset + offsetY
                                            }
                                        } else if offsetY < 0 {
                                            // Add some resistance for upward drag
                                            let y = 1.0 / (1.0 + exp(-1 * (abs(offsetY) / 50.0))) - 0.5
                                            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                                sheetOffset = dragStartOffset + y * max(offsetY, -20)
                                            }
                                        }
                                    }
                                    .onEnded { value in
                                        viewModel.setDragging(false)
                                        let offsetY = value.translation.height

                                        if offsetY > DuckPlayerContainer.Constants.dragThreshold || value.velocity.height > 50 {
                                            onDismiss(false) // User dismissed the pill
                                        } else if offsetY < -DuckPlayerContainer.Constants.dragThreshold || value.velocity.height < -50 {
                                            // Start presenting DuckPlayer immediately
                                            onPresentDuckPlayer()

                                        } else {
                                            withAnimation(.spring(duration: 0.2, bounce: 0.4)) {
                                                sheetOffset = calculateSheetOffset(for: viewModel.sheetVisible, containerHeight: containerHeight)
                                            }
                                        }
                                    }
                            )
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .onWidthChange { newWidth in
            sheetWidth = newWidth
        }
        .padding(.bottom, 20)
        .background(Color(designSystemColor: .panel))
        .overlay(
            Rectangle()
                .fill(Color(uiColor: UIColor { traitCollection in
                    switch traitCollection.userInterfaceStyle {
                    case .dark:
                        return .black
                    default:
                        return UIColor(designSystemColor: .border)
                    }
                }))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
                .alignmentGuide(.top) { _ in 0 },
            alignment: .top
        )
        .frame(maxWidth: .infinity)
        .offset(y: sheetOffset)

        .onAppear {

            // Always start with the initial large offset value
            sheetOffset = DuckPlayerContainer.Constants.initialOffsetValue

            // If the sheet should be visible, animate it into view after a tiny delay
            if viewModel.sheetVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    animateOffset(to: true)
                }
            }
        }

        .onChange(of: viewModel.sheetVisible) { sheetVisible in
            animateOffset(to: sheetVisible)
        }

        .onChange(of: containerHeight) { _ in
            animateOffset(to: viewModel.sheetVisible)
        }

        .onHeightChange { newHeight in
            sheetHeight = newHeight
            onHeightChange(newHeight)
        }
    }
}

// MARK: - View Extensions

extension View {
    func onWidthChange(perform action: @escaping (Double) -> Void) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: WidthPreferenceKey.self, value: geometry.size.width)
                    .onPreferenceChange(WidthPreferenceKey.self, perform: action)
            }
        )
    }

    func onHeightChange(perform action: @escaping (Double) -> Void) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: HeightPreferenceKey.self, value: geometry.size.height)
                    .onPreferenceChange(HeightPreferenceKey.self, perform: action)
            }
        )
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}
