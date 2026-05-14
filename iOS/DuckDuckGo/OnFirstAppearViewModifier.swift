//
//  OnFirstAppearViewModifier.swift
//  DuckDuckGo
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

import SwiftUI

/// A view modifier that executes a specified action only once when the view first appears.
///
/// Use this modifier to perform an action the first time the view becomes visible on the screen.
/// The action will not be executed again if the view reappears or is recreated.
///
/// Example:
/// ```swift
/// Text("Hello, World!")
///     .modifier(OnFirstAppearModifier {
///         print("The view has appeared for the first time.")
///     })
/// ```
///
/// - Parameter onFirstAppearAction: A closure to be executed the first time the view appears.
public struct OnFirstAppearViewModifier: ViewModifier {

    private let onFirstAppearAction: () -> Void
    private let onSubsequentAppearAction: (() -> Void)?
    @State private var hasAppeared = false

    public init(_ onFirstAppearAction: @escaping () -> Void, _ onSubsequentAppearAction: (() -> Void)?) {
        self.onFirstAppearAction = onFirstAppearAction
        self.onSubsequentAppearAction = onSubsequentAppearAction
    }

    public func body(content: Content) -> some View {
        content
            .onAppear {
                if hasAppeared {
                    onSubsequentAppearAction?()
                } else {
                    hasAppeared = true
                    onFirstAppearAction()
                }
            }
    }
}

extension View {

    /// Adds an action to perform that is executed only the first time before this view appears.
    ///
    /// - Parameter action: A closure to be executed the first time the view appears.
    /// - Returns: A view that will execute `action` only once when it appears.
    func onFirstAppear(_ onFirstAppearAction: @escaping () -> Void, subsequently subsequentActions: (() -> Void)? = nil) -> some View {
        return modifier(OnFirstAppearViewModifier(onFirstAppearAction, subsequentActions))
    }

}
