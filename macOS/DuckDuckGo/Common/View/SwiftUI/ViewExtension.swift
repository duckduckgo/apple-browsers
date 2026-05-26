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

private struct RoundedCorner: Shape {

    var radius: CGFloat = 0
    var corners: [NSBezierPath.Corners] = NSBezierPath.Corners.allCases

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(roundedRect: rect, forCorners: corners, cornerRadius: radius)
        return Path(path.asCGPath())
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
        content.task(priority: priority, action)
    }

}
