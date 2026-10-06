//
//  View+Cursor.swift
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
import AppKit

public extension View {
    /**
     * Displays `cursor` when the view is hovered.
     *
     * This modifier uses `.onHover` under the hood, so it takes an optional
     * closure parameter that would be called inside the `.onHover` modifier
     * before updating the cursor, removing the need to add a separate `.onHover`
     * modifier.
     */
    func cursor(_ cursor: NSCursor, onHover: ((Bool) -> Void)? = nil) -> some View {
        modifier(CursorModifier(cursor: cursor, onHoverChanged: onHover))
    }
}

private struct CursorModifier: ViewModifier {

    let cursor: NSCursor
    let onHoverChanged: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        content
            .onHover { inside in

                onHoverChanged?(inside)

                // Async dispatch is required in case a State variable update triggers view
                // re-rendering: a cursor set made inline is dropped along with the old rendering.
                // As seen on https://stackoverflow.com/a/67890394.
                //
                // Unconditional, because the re-render can just as well come from an ancestor's
                // own hover handler — a row that reveals a button on hover, say. Handling only the
                // `onHoverChanged` case left the cursor depending on which side the pointer
                // entered from.
                DispatchQueue.main.async {
                    updateCursor(isHovered: inside)
                }
            }
    }

    func updateCursor(isHovered: Bool) {
        if isHovered {
            cursor.push()
        } else {
            NSCursor.pop()
        }
    }
}
