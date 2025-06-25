//
//  DuckPlayerToastView.swift
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

import SwiftUI

private enum Constants {
    static let cornerRadius: CGFloat = 8
    static let backgroundColor: Color = .black.opacity(0.9)
    static let buttonColor: Color = .white.opacity(0.76)
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 100
    static let height: CGFloat = 50
    static let fadeAnimationDuration: TimeInterval = 0.2
    static let defaultVisibleDuration: TimeInterval = 3.0
}

enum ToastPosition {
    case top
    case bottom
}

@MainActor
protocol DuckPlayerToastViewModel {
    var message: AttributedString { get }
    var buttonTitle: String { get }
    var onButtonTapped: (() -> Void)? { get }
}

@MainActor
final class DefaultDuckPlayerToastViewModel: ObservableObject, DuckPlayerToastViewModel {
    @Published var opacity: CGFloat = 0
    let message: AttributedString
    let buttonTitle: String
    let onButtonTapped: (() -> Void)?
    let position: ToastPosition
    let offset: CGFloat?
    let timeout: TimeInterval?

    private var dismissTask: Task<Void, Never>?

    init(
        message: AttributedString,
        buttonTitle: String,
        onButtonTapped: (() -> Void)?,
        position: ToastPosition = .bottom,
        offset: CGFloat? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.message = message
        self.buttonTitle = buttonTitle
        self.onButtonTapped = onButtonTapped
        self.position = position
        self.offset = offset
        self.timeout = timeout
    }

    func appear(onDismiss: @escaping () -> Void) {
        // Cancel any existing dismiss task
        dismissTask?.cancel()

        // Animate in
        withAnimation(.easeIn(duration: Constants.fadeAnimationDuration)) {
            opacity = 1
        }

        // Schedule removal if timeout is set
        let visibleDuration = timeout ?? Constants.defaultVisibleDuration

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(visibleDuration * 1_000_000_000))

            if !Task.isCancelled {
                withAnimation(.easeOut(duration: Constants.fadeAnimationDuration)) {
                    opacity = 0
                }

                try? await Task.sleep(nanoseconds: UInt64(Constants.fadeAnimationDuration * 1_000_000_000))

                if !Task.isCancelled {
                    onDismiss()
                }
            }
        }
    }

    func cancel() {
        dismissTask?.cancel()
    }
}

struct DuckPlayerToastView: View {
    let message: AttributedString
    let buttonTitle: String?
    let onButtonTapped: (() -> Void)?
    let position: ToastPosition
    let offset: CGFloat?
    let timeout: TimeInterval?

    @State private var opacity: CGFloat = 0
    @State private var dismissTask: Task<Void, Never>?

    private(set) static var activeToast: UIView?

    init(
        message: AttributedString,
        buttonTitle: String? = nil,
        onButtonTapped: (() -> Void)? = nil,
        position: ToastPosition = .bottom,
        offset: CGFloat? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.message = message
        self.buttonTitle = buttonTitle
        self.onButtonTapped = onButtonTapped
        self.position = position
        self.offset = offset
        self.timeout = timeout
    }

    private var yPosition: CGFloat {
        switch position {
        case .top:
            let basePosition = Constants.verticalPadding
            return offset.map { basePosition + $0 } ?? basePosition
        case .bottom:
            let baseOffset = -Constants.verticalPadding
            return offset.map { baseOffset + $0 } ?? baseOffset
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full screen transparent button to handle outside taps
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissToast()
                    }

                HStack {
                    Text(message)
                        .lineLimit(3)
                        .daxBodyRegular()
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    if let buttonTitle, let onButtonTapped {
                        Button(
                            action: {
                                onButtonTapped()
                                dismissToast()
                            },
                            label: {
                                Text(buttonTitle)
                                    .daxBodyBold()
                                    .foregroundColor(Constants.buttonColor)
                            })
                    }
                }
                .padding()
                .background(Constants.backgroundColor)
                .cornerRadius(Constants.cornerRadius)
                .padding(.horizontal, Constants.horizontalPadding)
                .opacity(opacity)
                .frame(height: Constants.height)
                .position(
                    x: geometry.size.width / 2,
                    y: position == .top ? yPosition : geometry.size.height + yPosition
                )
                // Make the toast capture touches
                .contentShape(Rectangle())
                .allowsHitTesting(true)
            }
        }
        .onAppear {
            appear()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func appear() {
        dismissTask?.cancel()

        withAnimation(.easeIn(duration: Constants.fadeAnimationDuration)) {
            opacity = 1
        }

        let visibleDuration = timeout ?? Constants.defaultVisibleDuration
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(visibleDuration * 1_000_000_000))

            if !Task.isCancelled {
                dismissToast()
            }
        }
    }

    private func dismissToast() {
        withAnimation(.easeOut(duration: Constants.fadeAnimationDuration)) {
            opacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Constants.fadeAnimationDuration * 1_000_000_000))

            // Find the toast container and remove it from the superview
            if let activeToast = DuckPlayerToastView.activeToast {
                activeToast.removeFromSuperview()
                DuckPlayerToastView.activeToast = nil
            }
        }
    }

    // MARK: - Static Presentation Methods

    /// Presents a toast with the given configuration
    @MainActor
    static func present(
        message: AttributedString,
        buttonTitle: String? = nil,
        onButtonTapped: (() -> Void)? = nil,
        position: ToastPosition = .bottom,
        offset: CGFloat? = nil,
        timeout: TimeInterval? = nil
    ) {
        // First, remove any existing toast
        if let activeToast = activeToast {
            activeToast.removeFromSuperview()
            self.activeToast = nil
        }

        guard let window = UIApplication.shared.firstKeyWindow else { return }

        // Create the toast view
        let toastView = DuckPlayerToastView(
            message: message,
            buttonTitle: buttonTitle,
            onButtonTapped: onButtonTapped,
            position: position,
            offset: offset,
            timeout: timeout
        )

        // Create and configure hosting controller
        let hostingController = UIHostingController(rootView: toastView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = window.bounds

        // Store reference to the hosting view
        activeToast = hostingController.view

        // Add to window
        window.addSubview(hostingController.view)
    }
}
