//
//  TabBarTouchDragHandler.swift
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

import Cocoa

/// Starts item drags from on-screen touches: press and hold lifts an item, a plain swipe still scrolls.
///
/// The collection view is the dragging source, as in a mouse drag, so drop handling is shared.
final class TabBarTouchDragHandler: NSObject {

    init(collectionView: NSCollectionView) {
        super.init()

        // Touch screens need macOS 27.
        guard #available(macOS 27.0, *) else { return }

        let recognizer = NSPressGestureRecognizer(target: self, action: #selector(touchPressRecognized(_:)))
        // The default mask includes the primary mouse button, so a held click would also start a drag.
        recognizer.buttonMask = 0x0
        recognizer.allowedTouchTypes = .direct
        collectionView.addGestureRecognizer(recognizer)
    }

    @available(macOS 27.0, *)
    @objc private func touchPressRecognized(_ recognizer: NSPressGestureRecognizer) {
        guard recognizer.state == .began,
              let collectionView = recognizer.view as? NSCollectionView,
              let delegate = collectionView.delegate,
              let indexPath = collectionView.indexPathForItem(at: recognizer.location(in: collectionView)),
              let item = collectionView.item(at: indexPath),
              let writer = delegate.collectionView?(collectionView, pasteboardWriterForItemAt: indexPath) else { return }

        if !item.isSelected {
            // A mouse drag selects the item on mouse down, and the item's dragged state is only cleared by selection.
            delegate.collectionView?(collectionView, didChangeItemsAt: [indexPath], to: .forSelection)
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.draggingFrame = item.view.frame
        draggingItem.imageComponentsProvider = { item.draggingImageComponents }

        guard let session = collectionView.beginDraggingSession(items: [draggingItem], gesture: recognizer, source: collectionView) else { return }
        // NSCollectionView only reports the start of drags it began itself.
        delegate.collectionView?(collectionView, draggingSession: session, willBeginAt: NSEvent.mouseLocation, forItemsAt: [indexPath])
    }
}
