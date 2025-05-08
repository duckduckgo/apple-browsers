//
//  DraggingDestinationView.swift
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

/// Receives dragging events when registered with `.registerForDraggedTypes` and passes them to its next responder (superview or view controller)
internal class DraggingDestinationView: NSView {
    // MARK: - NSDraggingDestination

    override func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        return (nextResponder as? NSDraggingDestination)?.draggingEntered?(draggingInfo) ?? .none
    }

    override func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        return (nextResponder as? NSDraggingDestination)?.draggingUpdated?(draggingInfo) ?? .none
    }

    override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        return (nextResponder as? NSDraggingDestination)?.performDragOperation?(draggingInfo) ?? false
    }
}
