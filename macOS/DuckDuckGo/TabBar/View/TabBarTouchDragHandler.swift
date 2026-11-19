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

/// Starts item drags from on-screen touches, which scroll instead of producing the mouse drags `NSCollectionView` needs.
///
/// The collection view is the dragging source, as in a mouse drag, so drop handling is shared.
final class TabBarTouchDragHandler: NSObject {

    init(collectionView: NSCollectionView) {
        super.init()

        let recognizer = NSPanGestureRecognizer(target: self, action: #selector(touchPanRecognized(_:)))
        recognizer.buttonMask = 0x0
        recognizer.allowedTouchTypes = .direct
        collectionView.addGestureRecognizer(recognizer)

        if #available(macOS 27.0, *) {
            // One finger drags items, so scrolling takes two.
            recognizer.maximumNumberOfTouches = 1
            collectionView.enclosingScrollView?.minimumNumberOfTouchesForScrolling = 2
        }
    }

    @objc private func touchPanRecognized(_ recognizer: NSPanGestureRecognizer) {
        guard recognizer.state == .began,
              let collectionView = recognizer.view as? NSCollectionView,
              let event = NSApp.currentEvent,
              let indexPath = collectionView.indexPathForItem(at: recognizer.location(in: collectionView)),
              let item = collectionView.item(at: indexPath),
              let writer = collectionView.delegate?.collectionView?(collectionView, pasteboardWriterForItemAt: indexPath) else { return }

        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.draggingFrame = item.view.frame
        draggingItem.imageComponentsProvider = { item.draggingImageComponents }

        let session = collectionView.beginDraggingSession(with: [draggingItem], event: event, source: collectionView)
        // NSCollectionView only reports the start of drags it began itself.
        collectionView.delegate?.collectionView?(collectionView, draggingSession: session, willBeginAt: NSEvent.mouseLocation, forItemsAt: [indexPath])
    }
}
