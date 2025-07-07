//
//  ContextMenuPresenter.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

public typealias ContextMenuPresenterProvider = (NSWindow?) -> ContextMenuPresenting

@inlinable
public func DefaultContextMenuPresenterProvider() -> ContextMenuPresenterProvider { // swiftlint:disable:this identifier_name
    DefaultContextMenuPresenter.init
}

public protocol ContextMenuPresenting {
    var window: NSWindow? { get }
    func showContextMenu(_ menu: NSMenu)
}

public struct DefaultContextMenuPresenter: ContextMenuPresenting {

    public weak var window: NSWindow?

    public init(window: NSWindow? = nil) {
        self.window = window
    }

    public func showContextMenu(_ menu: NSMenu) {
        if !menu.items.isEmpty {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

}
