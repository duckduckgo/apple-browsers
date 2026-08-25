//
//  ReorderableForEach.swift
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
import UniformTypeIdentifiers

struct ReorderableInteractionConfiguration {
    let itemProvider: NSItemProvider
    let typeIdentifier: String
    let onDragBegan: (ObjectIdentifier?) -> Void
    let canHandleDrop: (ObjectIdentifier) -> Bool
    let onDropEntered: () -> Void
    let onDragEnded: (ObjectIdentifier) -> Void
}

private struct ReorderableInteractionConfigurationKey: EnvironmentKey {
    static let defaultValue: ReorderableInteractionConfiguration? = nil
}

extension EnvironmentValues {
    var reorderableInteractionConfiguration: ReorderableInteractionConfiguration? {
        get { self[ReorderableInteractionConfigurationKey.self] }
        set { self[ReorderableInteractionConfigurationKey.self] = newValue }
    }
}

struct ReorderableForEach<Data: Reorderable, ID: Hashable, Content: View, Preview: View>: View {

    typealias ContentBuilder = (Data) -> Content
    typealias PreviewBuilder = (Data) -> Preview

    private let data: [Data]
    private let id: KeyPath<Data, ID>
    private let isReorderingEnabled: Bool
    private let isReorderingHandledByContent: Bool

    private let content: ContentBuilder
    private let preview: PreviewBuilder?
    private let onMove: (_ from: IndexSet, _ to: Int) -> Void

    @State private var movedItem: Data?
    @State private var dragOrder: [Data]?
    @State private var activeDragSessionID: ObjectIdentifier?

    init(_ data: [Data],
         id: KeyPath<Data, ID>,
         @ViewBuilder content: @escaping ContentBuilder,
         onMove: @escaping (_ from: IndexSet, _ to: Int) -> Void) where Preview == EmptyView {
        self.data = data
        self.id = id
        self.isReorderingEnabled = true
        self.isReorderingHandledByContent = false
        self.content = content
        self.preview = nil
        self.onMove = onMove
    }

    init(_ data: [Data],
         id: KeyPath<Data, ID>,
         isReorderingEnabled: Bool = true,
         isReorderingHandledByContent: Bool = false,
         @ViewBuilder content: @escaping ContentBuilder,
         @ViewBuilder preview: @escaping (Data) -> Preview,
         onMove: @escaping (_ from: IndexSet, _ to: Int) -> Void) {
        self.data = data
        self.id = id
        self.isReorderingEnabled = isReorderingEnabled
        self.isReorderingHandledByContent = isReorderingHandledByContent
        self.content = content
        self.preview = preview
        self.onMove = onMove
    }

    var body: some View {
        ForEach(data, id: id) { item in
            contentForItem(item: item)
        }
    }

    @ViewBuilder
    private func contentForItem(item: Data) -> some View {
        switch item.trait {

        case .movable(let metadata) where isReorderingEnabled:
            let interactionConfiguration = ReorderableInteractionConfiguration(
                itemProvider: metadata.itemProvider,
                typeIdentifier: metadata.type.identifier,
                onDragBegan: { sessionID in
                    movedItem = item
                    if sessionID != nil {
                        dragOrder = data
                    }
                    activeDragSessionID = sessionID
                },
                canHandleDrop: { sessionID in
                    movedItem != nil && activeDragSessionID == sessionID
                },
                onDropEntered: { moveDraggedItem(over: item) },
                onDragEnded: { sessionID in
                    guard activeDragSessionID == sessionID else { return }
                    movedItem = nil
                    dragOrder = nil
                    activeDragSessionID = nil
                }
            )

            if isReorderingHandledByContent {
                content(item)
                    .environment(\.reorderableInteractionConfiguration, interactionConfiguration)
            } else if let preview {
                droppableContent(for: item, metadata: metadata)
                    .onDrag {
                        interactionConfiguration.onDragBegan(nil)
                        return interactionConfiguration.itemProvider
                    } preview: {
                        preview(item)
                    }
            } else {
                droppableContent(for: item, metadata: metadata)
                    .onDrag {
                        interactionConfiguration.onDragBegan(nil)
                        return interactionConfiguration.itemProvider
                    }
            }

        default:
            content(item)

        }
    }

    @ViewBuilder
    private func droppableContent(for item: Data, metadata: MoveMetadata) -> some View {
        content(item)
            .onDrop(of: [metadata.type], delegate: ReorderDropDelegate(
                data: data,
                item: item,
                onMove: onMove,
                movedItem: $movedItem))
    }

    private func moveDraggedItem(over item: Data) {
        var currentOrder = dragOrder ?? data
        guard item != movedItem,
              let current = movedItem,
              let from = currentOrder.firstIndex(of: current),
              let to = currentOrder.firstIndex(of: item)
        else { return }

        let fromIndices = IndexSet(integer: from)
        let toIndex = to > from ? to + 1 : to
        currentOrder.move(fromOffsets: fromIndices, toOffset: toIndex)
        dragOrder = currentOrder
        onMove(fromIndices, toIndex)
    }
}

private struct ReorderDropDelegate<Data: Reorderable>: DropDelegate {

    let data: [Data]
    let item: Data
    let onMove: (_ from: IndexSet, _ to: Int) -> Void

    @Binding var movedItem: Data?

    func dropEntered(info: DropInfo) {
        guard item != movedItem,
              let current = movedItem,
              let from = data.firstIndex(of: current),
              let to = data.firstIndex(of: item)
        else { return }

        if data[to] != current {
            let fromIndices = IndexSet(integer: from)
            let toIndex = to > from ? to + 1 : to
            onMove(fromIndices, toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        movedItem = nil
        return true
    }
}

extension ReorderableForEach where Data: Identifiable, ID == Data.ID {
    init(_ data: [Data],
         @ViewBuilder content: @escaping ContentBuilder,
         onMove: @escaping (_ from: IndexSet, _ to: Int) -> Void) where Preview == EmptyView {
        self.data = data
        self.id = \Data.id
        self.isReorderingEnabled = true
        self.isReorderingHandledByContent = false
        self.content = content
        self.preview = nil
        self.onMove = onMove
    }

    init(_ data: [Data],
         @ViewBuilder content: @escaping ContentBuilder,
         @ViewBuilder preview: @escaping PreviewBuilder,
         onMove: @escaping (_ from: IndexSet, _ to: Int) -> Void) {
        self.data = data
        self.id = \Data.id
        self.isReorderingEnabled = true
        self.isReorderingHandledByContent = false
        self.content = content
        self.preview = preview
        self.onMove = onMove
    }
}

struct MoveMetadata {
    var itemProvider: NSItemProvider
    var type: UTType
}

enum ReorderableTrait {
    case stationary
    case movable(MoveMetadata)
}

protocol Reorderable: Hashable {
    var trait: ReorderableTrait { get }
}
