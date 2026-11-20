//
//  WebExtensionWindowOrder.swift
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

import Foundation

/// Numbers the windows of an extension context in the order they are first handed to WebKit.
///
/// WebKit gives a window its `windowId` from an increasing counter when it first receives the window, so the
/// n-th smallest `windowId` an extension knows is the n-th window of this order.
@MainActor
public final class WebExtensionWindowOrder {

    public static let shared = WebExtensionWindowOrder()

    private final class Numbering {
        let numbers = NSMapTable<AnyObject, NSNumber>.weakToStrongObjects()
        var next = 1
    }

    private var numberings: [String: Numbering] = [:]

    public init() {}

    /// Gives the window its number in the context (the extension's unique identifier), once. Call it wherever the
    /// window is handed to WebKit.
    public func register(_ window: AnyObject, in contextIdentifier: String) {
        let numbering = numbering(for: contextIdentifier)
        guard numbering.numbers.object(forKey: window) == nil else { return }
        numbering.numbers.setObject(NSNumber(value: numbering.next), forKey: window)
        numbering.next += 1
    }

    /// The open windows of the context in the order they were handed to WebKit.
    public func windows(in contextIdentifier: String) -> [AnyObject] {
        let numbers = numbering(for: contextIdentifier).numbers
        let windows = numbers.keyEnumerator().allObjects.map { $0 as AnyObject }
        return windows.sorted { number(of: $0, in: numbers) < number(of: $1, in: numbers) }
    }

    private func number(of window: AnyObject, in numbers: NSMapTable<AnyObject, NSNumber>) -> Int {
        numbers.object(forKey: window)?.intValue ?? 0
    }

    private func numbering(for contextIdentifier: String) -> Numbering {
        if let numbering = numberings[contextIdentifier] { return numbering }
        let numbering = Numbering()
        numberings[contextIdentifier] = numbering
        return numbering
    }
}
