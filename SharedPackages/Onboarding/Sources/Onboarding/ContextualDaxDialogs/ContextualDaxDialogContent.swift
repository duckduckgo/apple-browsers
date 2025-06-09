//
//  ContextualDaxDialogContent.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation
import SwiftUI
import Combine

#if canImport(UIKit)
typealias PlatformFont = UIFont
#else
typealias PlatformFont = NSFont
#endif

public struct ContextualDaxDialogContent: View {

    public enum Orientation: Equatable {
        case verticalStack
        case horizontalStack(alignment: VerticalAlignment)
    }

    let title: String?
    let titleFont: Font?
    let messageFont: Font?
    public let message: NSAttributedString
    let list: [ContextualOnboardingListItem]
    let listAction: ((_ item: ContextualOnboardingListItem) -> Void)?
    let customView: AnyView?
    let customActionView: AnyView?
    let orientation: Orientation

    private let itemsToAnimate: [DisplayableTypes]

    var skipAnimations: Binding<Bool>

    public init(
        orientation: Orientation = .verticalStack,
        title: String? = nil,
        titleFont: Font? = nil,
        message: NSAttributedString,
        messageFont: Font? = nil,
        list: [ContextualOnboardingListItem] = [],
        listAction: ((_: ContextualOnboardingListItem) -> Void)? = nil,
        customView: AnyView? = nil,
        customActionView: AnyView? = nil,
        skipAnimations: Binding<Bool> = .constant(false)
    ) {
        self.title = title
        self.titleFont = titleFont
        self.message = message
        self.messageFont = messageFont
        self.list = list
        self.listAction = listAction
        self.customView = customView
        self.customActionView = customActionView
        self.orientation = orientation
        self.skipAnimations = skipAnimations

        var itemsToAnimate: [DisplayableTypes] = []
        if title != nil {
            itemsToAnimate.append(.title)
        }
        itemsToAnimate.append(.message)
        if !list.isEmpty {
            itemsToAnimate.append(.list)
        }
        if customView != nil {
            itemsToAnimate.append(.customView)
        }
        if customActionView != nil {
            itemsToAnimate.append(.button)
        }

        self.itemsToAnimate = itemsToAnimate
    }

    @State private var startTypingTitle: Bool = false
    @State private var startTypingMessage: Bool = false
    @State private var nonTypingAnimatableItems: NonTypingAnimatableItems = []

    public var body: some View {
        Group {
            if orientation == .verticalStack {
                VStack {
                    typingElements
                    nonTypingElements
                }
            } else if case .horizontalStack(let alignment) = orientation {
                HStack(alignment: alignment, spacing: 5) {
                    typingElements
                    Spacer()
                    nonTypingElements
                }
                .frame(width: 488)
            }
        }
        .onAppear {
            Task { @MainActor in
                try await Task.sleep(interval: 0.3)
                startAnimating()
            }
        }
    }

    @ViewBuilder var typingElements: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleView
            messageView
        }
    }

    @ViewBuilder var nonTypingElements: some View {
        VStack(alignment: .leading, spacing: 16) {
            listView
                .visibility(nonTypingAnimatableItems.contains(.list) ? .visible : .invisible)
            extraView
                .visibility(nonTypingAnimatableItems.contains(.customView) ? .visible : .invisible)
            actionView
                .visibility(nonTypingAnimatableItems.contains(.button) ? .visible : .invisible)
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if let title {
            let animatingText = AnimatableTypingText(title, startAnimating: $startTypingTitle, skipAnimation: skipAnimations, onTypingFinished: {
                self.startTypingMessage = true
            })

            if let titleFont {
                animatingText.font(titleFont)
            } else {
                animatingText
            }
        }
    }

    @ViewBuilder
    private var messageView: some View {
        let animatingText = AnimatableTypingText(message, startAnimating: $startTypingMessage, skipAnimation: skipAnimations, onTypingFinished: {
            animateNonTypingItems()
        })
        if let messageFont {
            animatingText.font(messageFont)
        } else {
            animatingText
        }
    }

    @ViewBuilder
    private var listView: some View {
        if let listAction {
            ContextualOnboardingListView(list: list, action: listAction)
        }
    }

    @ViewBuilder
    private var extraView: some View {
        if let customView {
            customView
        }
    }

    @ViewBuilder
    private var actionView: some View {
        if let customActionView {
            customActionView
        }
    }

    enum DisplayableTypes {
        case title
        case message
        case list
        case customView
        case button
    }
}

struct NonTypingAnimatableItems: OptionSet {
    let rawValue: Int

    static let list = NonTypingAnimatableItems(rawValue: 1 << 0)
    static let customView = NonTypingAnimatableItems(rawValue: 1 << 1)
    static let button = NonTypingAnimatableItems(rawValue: 1 << 2)
}

// MARK: - Auxiliary Functions

extension ContextualDaxDialogContent {

    private func completeAnimations() {
        // Immediately set all states to their final values
        skipAnimations.wrappedValue = true
        startTypingTitle = false
        startTypingMessage = false
        nonTypingAnimatableItems = [.list, .customView, .button]
    }

    private func startAnimating() {
        if skipAnimations.wrappedValue {
            completeAnimations()
            return
        }

        if itemsToAnimate.contains(.title) {
            startTypingTitle = true
        } else if itemsToAnimate.contains(.message) {
            startTypingMessage = true
        }
    }

    private func animateNonTypingItems() {
        if skipAnimations.wrappedValue {
            completeAnimations()
            return
        }

        // Remove typing items and animate sequentially non typing items
        let nonTypingItems = itemsToAnimate.filter { $0 != .title && $0 != .message }

        nonTypingItems.enumerated().forEach { index, item in
            let delayForItem = Metrics.animationDelay * Double(index + 1)
            withAnimation(.easeIn(duration: Metrics.animationDuration).delay(delayForItem)) {
                switch item {
                case .title, .message:
                    // Typing items. they don't need to animate sequentially.
                    break
                case .list:
                    nonTypingAnimatableItems.insert(.list)
                case .customView:
                    nonTypingAnimatableItems.insert(.customView)
                case .button:
                    nonTypingAnimatableItems.insert(.button)
                }
            }
        }
    }
}

// MARK: - Metrics

enum Metrics {
    static let animationDuration = 0.25
    static let animationDelay = 0.3
}

// MARK: - Preview

#Preview("Intro Dialog - text") {
    let fullString = "Instantly clear your browsing activity with the Fire Button.\n\n Give it a try! ☝️"
    let boldString = "Fire Button."

    let attributedString = NSMutableAttributedString(string: fullString)
    let boldFontAttribute: [NSAttributedString.Key: Any] = [
        .font: PlatformFont.systemFont(ofSize: 15, weight: .bold)
    ]

    if let boldRange = fullString.range(of: boldString) {
        let nsBoldRange = NSRange(boldRange, in: fullString)
        attributedString.addAttributes(boldFontAttribute, range: nsBoldRange)
    }

    return ContextualDaxDialogContent(message: attributedString)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Intro Dialog - text and button") {
    let contextualText = NSMutableAttributedString(string: "Sabrina is the best\n\nBelieve me! ☝️")
    return ContextualDaxDialogContent(
        message: contextualText,
        customActionView: AnyView(Button("Got it!", action: {})))
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Intro Dialog - title, text, image and button") {
    let contextualText = NSMutableAttributedString(string: "Sabrina is the best\n\nBelieve me! ☝️")
    let extraView = {
        HStack {
            Spacer()
            Image("Sync-Desktop-New-128")
            Spacer()
        }
    }()

    return ContextualDaxDialogContent(
        title: "Who is the best?",
        message: contextualText,
        customView: AnyView(extraView),
        customActionView: AnyView(Button("Got it!", action: {})))
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Intro Dialog - title, text, list") {
    let contextualText = NSMutableAttributedString(string: "Sabrina is the best!\n\n Alessandro is ok I guess...")
    let list = [
        ContextualOnboardingListItem.search(title: "Search"),
        ContextualOnboardingListItem.site(title: "Website"),
        ContextualOnboardingListItem.surprise(title: "Surprise", visibleTitle: "Surpeise me!"),
    ]
    return ContextualDaxDialogContent(
        title: "Who is the best?",
        message: contextualText,
        list: list,
        listAction: { _ in })
    .padding()
    .preferredColorScheme(.light)
}

#Preview("en_GB list") {
    ContextualDaxDialogContent(title: "title",
                               message: NSAttributedString(string: "this is a message"),
                               list: OnboardingSuggestedSitesProvider(countryProvider: Locale(identifier: "en_GB"), surpriseItemTitle: "surperise").list,
                        listAction: { _ in })
    .padding()
}

#Preview("en_US list") {
    ContextualDaxDialogContent(title: "title",
                               message: NSAttributedString(string: "this is a message"),
                               list: OnboardingSuggestedSitesProvider(countryProvider: Locale(identifier: "en_US"), surpriseItemTitle: "surprise").list,
                        listAction: { _ in })
    .padding()
}
