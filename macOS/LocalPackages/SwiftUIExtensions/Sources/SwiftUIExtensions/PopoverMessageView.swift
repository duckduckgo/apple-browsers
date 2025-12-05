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

public final class PopoverMessageViewModel: ObservableObject {
    // MARK: - Content Properties
    @Published public var title: String?
    @Published public var message: String
    @Published public var image: NSImage?

    // MARK: - Layout & Behavior Configuration
    public var popoverStyle: PopoverStyle
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

    public init(title: String?,
                message: String,
                image: NSImage? = nil,
                popoverStyle: PopoverStyle = .basic,
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
        self.popoverStyle = popoverStyle
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
        HStack(spacing: 8) {
            if let image = viewModel.image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 24, height: 24)
            }

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
                    .padding(.leading, -6)
                    .padding(.trailing, 2)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
    }
}
