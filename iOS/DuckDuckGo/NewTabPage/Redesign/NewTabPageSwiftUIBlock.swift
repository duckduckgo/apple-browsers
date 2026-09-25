//
//  NewTabPageSwiftUIBlock.swift
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
import UIKit

/// A New Tab Page block whose content is a SwiftUI view.
final class NewTabPageSwiftUIBlock<Content: View>: NewTabPageBlock {

    let id: NewTabPageBlockID

    private let hostingController: UIHostingController<NewTabPageBlockContent<Content>>

    var viewController: UIViewController { hostingController }

    init(id: NewTabPageBlockID, rootView: Content) {
        self.id = id

        // The page already positions blocks inside its own safe area, so a hosting controller
        // applying the safe area again would inset the block a second time.
        hostingController = UIHostingController(rootView: NewTabPageBlockContent(content: rootView), ignoreSafeArea: true)
        hostingController.view.backgroundColor = .clear
        if #available(iOS 16.0, *) {
            // The UIKit stack must resize when SwiftUI content changes, including See All/See Less.
            hostingController.sizingOptions = [.intrinsicContentSize]
        } else {
            // iOS 15 does not automatically notify the UIKit stack when SwiftUI's ideal
            // height changes. Observe the content at its proposed width, including rotation.
            hostingController.rootView.onHeightChanged = { [weak hostingController] in
                hostingController?.view.invalidateIntrinsicContentSize()
                hostingController?.view.superview?.setNeedsLayout()
            }
        }
    }
}

private struct NewTabPageBlockContent<Content: View>: View {
    let content: Content
    var onHeightChanged: (() -> Void)?

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: NewTabPageBlockHeightKey.self, value: geometry.size.height)
                }
            }
            .onPreferenceChange(NewTabPageBlockHeightKey.self) { _ in
                onHeightChanged?()
            }
            // UIKit can resize the host before SwiftUI finishes animating its content.
            // Keep the block's top edge fixed throughout that height change.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct NewTabPageBlockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
