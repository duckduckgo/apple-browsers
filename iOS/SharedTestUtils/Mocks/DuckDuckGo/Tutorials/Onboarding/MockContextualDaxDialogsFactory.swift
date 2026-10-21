//
//  MockContextualDaxDialogsFactory.swift
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
@testable import DuckDuckGo

final class MockContextualDaxDialogsFactory: ContextualDaxDialogsFactory {
    private(set) var didCallMakeView = false
    private(set) var capturedSpec: DaxDialogs.BrowsingSpec?
    private(set) var capturedDelegate: ContextualOnboardingDelegate?

    func makeView(for spec: DaxDialogs.BrowsingSpec, delegate: ContextualOnboardingDelegate, onSizeUpdate: @escaping () -> Void) -> UIHostingController<AnyView> {
        didCallMakeView = true
        capturedSpec = spec
        capturedDelegate = delegate
        return UIHostingController(rootView: AnyView(EmptyView()))
    }
}
