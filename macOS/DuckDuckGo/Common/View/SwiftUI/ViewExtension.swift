//
//  ViewExtension.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

extension View {

    /**
     * Rounds corners specified by `corners` using given `radius`.
     */
    func cornerRadius(_ radius: CGFloat, corners: [NSBezierPath.Corners]) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

}

extension View {

    @available(macOS, obsoleted: 14.0, message: "This needs to be removed as it‘s no longer necessary.")
    @ViewBuilder
    func legacyOnDismiss(_ onDismiss: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self

        } else if let presentationModeKey = \EnvironmentValues.presentationMode as? WritableKeyPath {
            // hacky way to set the @Environment.presentationMode.
            // here we downcast a (non-writable) \.presentationMode KeyPath to a WritableKeyPath
            self.environment(presentationModeKey, Binding<PresentationMode>(onDismiss: onDismiss))
        } else {
            legacyMacOS11OnDismiss(onDismiss)
        }
    }

    @available(macOS, deprecated: 12.0, message: "This needs to be removed when macOS 11 support is dropped.")
    private func legacyMacOS11OnDismiss(_ onDismiss: @escaping () -> Void) -> some View {
        self.environment(\.legacyDismiss, onDismiss)
    }
}

extension Binding where Value == PresentationMode {

    init(isPresented: Bool = true, onDismiss: @escaping () -> Void) {
        // PresentationMode is a struct with a single isPresented property and a (statically dispatched) mutating function
        // This technically makes it equal to a Bool variable (MemoryLayout<PresentationMode>.size == MemoryLayout<Bool>.size == 1)
        var isPresented = isPresented
        self.init {
            // just return the Bool as a PresentationMode
            unsafeBitCast(isPresented, to: PresentationMode.self)
        } set: { newValue in
            // set it back
            isPresented = newValue.isPresented
            // and call the dismiss callback
            if !isPresented {
                onDismiss()
            }
        }
    }

}

@available(macOS, deprecated: 12.0, message: "This needs to be removed when macOS 11 support is dropped.")
struct DismissAction {
    let dismiss: () -> Void
    public func callAsFunction() {
        dismiss()
    }
}

@available(macOS, deprecated: 12.0, message: "This needs to be removed when macOS 11 support is dropped.")
struct LegacyDismissAction: EnvironmentKey {
    static var defaultValue: () -> Void { { } }
}

extension EnvironmentValues {
    @available(macOS, deprecated: 12.0, message: "This extension needs to be removed when macOS 11 support is dropped.")
    var dismiss: DismissAction {
        DismissAction {
            if \EnvironmentValues.presentationMode is WritableKeyPath {
                presentationMode.wrappedValue.dismiss()
            } else {
                self[LegacyDismissAction.self]()
            }
        }
    }
    @available(macOS, deprecated: 12.0, message: "This extension needs to be removed when macOS 11 support is dropped.")
    fileprivate var legacyDismiss: () -> Void {
        get {
            self[LegacyDismissAction.self]
        }
        set {
            self[LegacyDismissAction.self] = newValue
        }
    }
}

private struct RoundedCorner: Shape {

    var radius: CGFloat = 0
    var corners: [NSBezierPath.Corners] = NSBezierPath.Corners.allCases

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(roundedRect: rect, forCorners: corners, cornerRadius: radius)
        return Path(path.asCGPath())
    }
}

extension View {

    @available(macOS, deprecated: 12.0, message: "This extension needs to be removed when macOS 11 support is dropped.")
    @_disfavoredOverload
    @inlinable func task(@_inheritActorContext _ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(ViewAsyncTaskModifier(priority: .userInitiated, action: action))
    }

}

public struct ViewAsyncTaskModifier: ViewModifier {

    private let priority: TaskPriority
    private let action: @Sendable () async -> Void

    public init(priority: TaskPriority, action: @escaping @Sendable () async -> Void) {
        self.priority = priority
        self.action = action
        self.task = nil
    }

    @State private var task: Task<Void, Never>?

    public func body(content: Content) -> some View {
        if #available(macOS 12.0, *) {
            content.task(priority: priority, action)
        } else {
            content
                .onAppear {
                    self.task = Task {
                        await action()
                    }
                }
                .onDisappear {
                    self.task?.cancel()
                }
        }
    }

}
