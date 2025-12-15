//
//  PopoverMessageView.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import AppKit
import Foundation
import SwiftUI

public enum PopoverStyle {
    case basic
    case featureDiscovery
}

public enum PopoverButtonLayout {
    case horizontal
    case vertical
}

public enum PopoverButtonStyle {
    case standard
    case link
}

public struct PopoverConfiguration {
    public var style: PopoverStyle
    public var buttonLayout: PopoverButtonLayout
    public var imageSize: CGSize?
    public var buttonStyle: PopoverButtonStyle
    public var accentColor: Color?

    public init(
        style: PopoverStyle = .basic,
        buttonLayout: PopoverButtonLayout = .horizontal,
        imageSize: CGSize? = nil,
        buttonStyle: PopoverButtonStyle = .standard,
        accentColor: Color? = nil
    ) {
        self.style = style
        self.buttonLayout = buttonLayout
        self.imageSize = imageSize
        self.buttonStyle = buttonStyle
        self.accentColor = accentColor
    }

    /// Default configuration matching current behavior
    public static let `default` = PopoverConfiguration(
        style: .basic,
        buttonLayout: .horizontal,
        imageSize: nil,
        buttonStyle: .standard,
        accentColor: nil
    )

    /// Feature discovery style with 24x24 image
    public static let featureDiscovery = PopoverConfiguration(
        style: .featureDiscovery,
        buttonLayout: .horizontal,
        imageSize: CGSize(width: 24, height: 24),
        buttonStyle: .standard,
        accentColor: nil
    )

    /// Feature discovery with vertical button layout
    public static let featureDiscoveryVertical = PopoverConfiguration(
        style: .featureDiscovery,
        buttonLayout: .vertical,
        imageSize: CGSize(width: 76, height: 76),
        buttonStyle: .link,
        accentColor: nil
    )
}

public final class PopoverMessageViewModel: ObservableObject {
    // MARK: - Content Properties
    @Published public var title: String?
    @Published public var message: String
    @Published public var image: NSImage?

    // MARK: - Configuration
    public var configuration: PopoverConfiguration

    // MARK: - Layout & Behavior Configuration
    @Published public var maxWidth: CGFloat?
    public var shouldShowCloseButton: Bool
    var shouldPresentMultiline: Bool

    // MARK: - Button Configuration
    @Published var buttonText: String?
    @Published public private(set) var buttonAction: (() -> Void)?

    // MARK: - Action Callbacks
    public private(set) var clickAction: (() -> Void)?
    public var dismissAction: (() -> Void)?
    public private(set) var onClose: (() -> Void)?

    // MARK: - Convenience Accessors
    public var popoverStyle: PopoverStyle { configuration.style }
    public var buttonLayout: PopoverButtonLayout { configuration.buttonLayout }
    public var imageSize: CGSize? { configuration.imageSize }
    public var buttonStyle: PopoverButtonStyle { configuration.buttonStyle }
    public var accentColor: Color? { configuration.accentColor }

    public init(title: String?,
                message: String,
                image: NSImage? = nil,
                configuration: PopoverConfiguration = .default,
                maxWidth: CGFloat? = nil,
                shouldShowCloseButton: Bool = false,
                shouldPresentMultiline: Bool = true,
                buttonText: String? = nil,
                buttonAction: (() -> Void)? = nil,
                clickAction: (() -> Void)? = nil,
                dismissAction: (() -> Void)? = nil,
                onClose: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.image = image
        self.configuration = configuration
        self.maxWidth = maxWidth
        self.shouldShowCloseButton = shouldShowCloseButton
        self.shouldPresentMultiline = shouldPresentMultiline
        self.buttonText = buttonText
        self.buttonAction = buttonAction
        self.clickAction = clickAction
        self.dismissAction = dismissAction
        self.onClose = onClose
    }

    /// Legacy initializer for backward compatibility
    public init(title: String?,
                message: String,
                image: NSImage? = nil,
                popoverStyle: PopoverStyle,
                maxWidth: CGFloat? = nil,
                shouldShowCloseButton: Bool = false,
                shouldPresentMultiline: Bool = true,
                buttonText: String? = nil,
                buttonAction: (() -> Void)? = nil,
                buttonLayout: PopoverButtonLayout = .horizontal,
                clickAction: (() -> Void)? = nil,
                dismissAction: (() -> Void)? = nil,
                onClose: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.image = image
        self.configuration = PopoverConfiguration(
            style: popoverStyle,
            buttonLayout: buttonLayout,
            imageSize: popoverStyle == .featureDiscovery ? CGSize(width: 24, height: 24) : nil,
            buttonStyle: .standard
        )
        self.maxWidth = maxWidth
        self.shouldShowCloseButton = shouldShowCloseButton
        self.shouldPresentMultiline = shouldPresentMultiline
        self.buttonText = buttonText
        self.buttonAction = buttonAction
        self.clickAction = clickAction
        self.dismissAction = dismissAction
        self.onClose = onClose
    }
}

public struct PopoverMessageView: View {
    @ObservedObject public var viewModel: PopoverMessageViewModel

    public init(viewModel: PopoverMessageViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        contentView
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.clickAction?()
                viewModel.dismissAction?()
            }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.popoverStyle {
        case .basic:
            if let title = viewModel.title {
                messageWithTitleBody(title)
            } else {
                messageBody
            }
        case .featureDiscovery:
            featureDiscovery
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        HStack(alignment: .top) {
            if let image = viewModel.image {
                Image(nsImage: image)
                    .padding(.top, 3)
            }

            Text(viewModel.message)
                .font(.body)
                .fontWeight(.bold)
                .padding(.leading, 2)
                .frame(minHeight: 22)
                .lineLimit(nil)
                .if(viewModel.shouldPresentMultiline) { view in
                    view.frame(width: viewModel.maxWidth ?? 160, alignment: .leading)
                }

            if let text = viewModel.buttonText,
               let action = viewModel.buttonAction {
                Button(text, action: {
                    action()
                    viewModel.dismissAction?()
                })
                .padding(.top, 2)
                .padding(.leading, 4)
            }

            if viewModel.shouldShowCloseButton {
                Button(action: {
                    viewModel.onClose?()
                    viewModel.dismissAction?()
                }) {
                    Image(.updateNotificationClose)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, viewModel.buttonText != nil ? 4 : 0)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func messageWithTitleBody(_ title: String) -> some View {
        HStack(spacing: 12) {
            if let image = viewModel.image {
                Image(nsImage: image)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.bold)
                    .frame(minHeight: 22)
                    .lineLimit(nil)
                Text(viewModel.message)
                    .font(.body)
                    .frame(minHeight: 22)
                    .lineLimit(nil)
            }
            .padding(.leading, 8)
            .if(viewModel.shouldPresentMultiline) { view in
                view.frame(width: viewModel.maxWidth ?? 300, alignment: .leading)
            }

            if let text = viewModel.buttonText,
               let action = viewModel.buttonAction {
                Button(text, action: {
                    action()
                    viewModel.dismissAction?()
                })
                .padding(.top, 2)
                .padding(.leading, 4)
            }

            if viewModel.shouldShowCloseButton {
                VStack(spacing: 0) {
                    Button(action: {
                        viewModel.onClose?()
                        viewModel.dismissAction?()
                    }) {
                        Image(.updateNotificationClose)
                        .frame(width: 16, height: 16)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, -4)
                    .padding(.trailing, -8)

                    Spacer()
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var featureDiscovery: some View {
        switch viewModel.buttonLayout {
        case .horizontal:
            featureDiscoveryHorizontal
        case .vertical:
            featureDiscoveryVertical
        }
    }

    @ViewBuilder
    private var featureDiscoveryHorizontal: some View {
        HStack(spacing: 8) {
            featureDiscoveryImage

            VStack(alignment: .leading, spacing: -4) {
                if let title = viewModel.title {
                    Text(title)
                        .font(.body)
                        .fontWeight(.bold)
                        .frame(minHeight: 22)
                        .lineLimit(nil)
                        .padding(.bottom, -1)
                }
                Text(viewModel.message)
                    .font(.body)
                    .frame(minHeight: 22)
                    .lineLimit(nil)
            }
            .if(viewModel.shouldPresentMultiline) { view in
                view.frame(width: viewModel.maxWidth ?? 300, alignment: .leading)
            }

            if let text = viewModel.buttonText,
               let action = viewModel.buttonAction {
                actionButton(text: text, action: action)
                    .padding(.top, 2)
                    .padding(.leading, 4)
            }

            if viewModel.shouldShowCloseButton {
                VStack(spacing: 0) {
                    closeButton
                    Spacer()
                }
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var featureDiscoveryVertical: some View {
        HStack(alignment: .top, spacing: 8) {
            featureDiscoveryImage

            VStack(alignment: .leading, spacing: 4) {
                if let title = viewModel.title {
                    Text(title)
                        .font(.body)
                        .fontWeight(.bold)
                        .frame(minHeight: 22)
                        .lineLimit(nil)
                }
                Text(viewModel.message)
                    .font(.body)
                    .frame(minHeight: 22)
                    .lineLimit(nil)

                if let text = viewModel.buttonText,
                   let action = viewModel.buttonAction {
                    actionButton(text: text, action: action)
                        .padding(.top, 4)
                }
            }
            .if(viewModel.shouldPresentMultiline) { view in
                view.frame(width: viewModel.maxWidth ?? 300, alignment: .leading)
            }

            if viewModel.shouldShowCloseButton {
                closeButton
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var featureDiscoveryImage: some View {
        if let image = viewModel.image {
            let size = viewModel.imageSize ?? CGSize(width: 24, height: 24)
            Image(nsImage: image)
                .resizable()
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func actionButton(text: String, action: @escaping () -> Void) -> some View {
        switch viewModel.buttonStyle {
        case .standard:
            Button(text, action: {
                action()
                viewModel.dismissAction?()
            })
        case .link:
            Button(action: {
                action()
                viewModel.dismissAction?()
            }) {
                Text(text)
                    .foregroundColor(viewModel.accentColor ?? .accentColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        Button(action: {
            viewModel.onClose?()
            viewModel.dismissAction?()
        }) {
            Image(.updateNotificationClose)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, -6)
        .padding(.trailing, 2)
    }
}
