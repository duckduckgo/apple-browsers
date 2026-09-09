//
//  SwiftUIBlock.swift
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
final class SwiftUIBlock<Content: View>: NewTabPageBlock {

    let id: String

    private let hostingController: UIHostingController<Content>

    var viewController: UIViewController { hostingController }

    init(id: String, rootView: Content) {
        self.id = id

        // The page already positions blocks inside its own safe area, so a hosting controller
        // applying the safe area again would inset the block a second time.
        hostingController = UIHostingController(rootView: rootView, ignoreSafeArea: true)
        hostingController.view.backgroundColor = .clear
    }
}
