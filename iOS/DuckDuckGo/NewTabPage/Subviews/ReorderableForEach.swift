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

struct ReorderableForEach<Data: Reorderable, ID: Hashable, Content: View, Preview: View>: View {

    typealias ContentBuilder = (Data) -> Content
    typealias PreviewBuilder = (Data) -> Preview

    private let data: [Data]
    private let id: KeyPath<Data, ID>
    private let isReorderingEnabled: Bool

    private let content: ContentBuilder
    private let preview: PreviewBuilder?
    private let onMove: (_ from: IndexSet, _ to: Int) -> Void
    private let onMoveFinished: () -> Void
    private let onDragActivityChanged: ((Bool) -> Void)?

    @State private var movedItem: Data?
    @State private var didMove = false
    @State private var activeDragSessionID: ObjectIdentifier?

    init(_ data: [Data],
         id: KeyPath<Data, ID>,
         @ViewBuilder content: @escaping ContentBuilder,
         onMove: @escaping (_ from: IndexSet, _ to: Int) -> Void) where Preview == EmptyView {
        self.data = data
        self.id = id
        self.isReorderingEnabled = true
        self.onDragActivityChanged = nil
        self.content = content
        self.preview = nil
        self.onMove = onMove
        self.onMoveFinished = {}
    }

    init(_ data: [Data],
         id: KeyPath<Data, ID>,
         isReorderingEnabled: Bool = true,
         onDragActivityChanged: ((Bool) -> Void)? = nil,
         @ViewBuilder content: @escaping ContentBuilder,
         @ViewBuilder preview: @escaping (Data) -> Preview,
         onMove: @escaping (_ from: IndexSet, _ to: Int) -> Void,
         onMoveFinished: @escaping () -> Void) {
        self.data = data
        self.id = id
        self.isReorderingEnabled = isReorderingEnabled
        self.onDragActivityChanged = onDragActivityChanged
        self.content = content
        self.preview = preview
        self.onMove = onMove
        self.onMoveFinished = onMoveFinished
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
            if let onDragActivityChanged, let preview {
                ReorderDragSource(content: content(item), preview: preview(item), itemProvider: metadata.itemProvider,
                                  onBegin: { sessionID in
                    activeDragSessionID = sessionID
                    movedItem = item
                    didMove = false
                    onDragActivityChanged(true)
                }, onEnd: { sessionID in
                    // A previous drag's drop animation can finish after the next drag starts.
                    guard activeDragSessionID == sessionID else { return }
                    activeDragSessionID = nil
                    movedItem = nil
                    if didMove {
                        didMove = false
                        onMoveFinished()
                    }
                    onDragActivityChanged(false)
                })
                .onDrop(of: [metadata.type], delegate: dropDelegate(for: item))
            } else if let preview {
                droppableContent(for: item, metadata: metadata)
                    .onDrag {
                        movedItem = item
                        didMove = false
                        return metadata.itemProvider
                    } preview: {
                        preview(item)
                    }
            } else {
                droppableContent(for: item, metadata: metadata)
                    .onDrag {
                        movedItem = item
                        didMove = false
                        return metadata.itemProvider
                    }
            }

        default:
            content(item)

        }
    }

    @ViewBuilder
    private func droppableContent(for item: Data, metadata: MoveMetadata) -> some View {
        content(item)
            .onDrop(of: [metadata.type], delegate: dropDelegate(for: item))
    }

    private func dropDelegate(for item: Data) -> ReorderDropDelegate<Data> {
        ReorderDropDelegate(data: data,
                            item: item,
                            onMove: onMove,
                            onMoveFinished: onMoveFinished,
                            movedItem: $movedItem,
                            didMove: $didMove)
    }
}

/// Track each native session rather than treating SwiftUI's item-provider request
/// as a drag-start notification. The end callback also covers cancelled drags.
private struct ReorderDragSource<Content: View, Preview: View>: UIViewControllerRepresentable {
    let content: Content
    let preview: Preview
    let itemProvider: NSItemProvider
    let onBegin: (ObjectIdentifier) -> Void
    let onEnd: (ObjectIdentifier) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(source: self)
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        let interaction = UIDragInteraction(delegate: context.coordinator)
        interaction.isEnabled = true
        controller.view.addInteraction(interaction)
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        context.coordinator.source = self
        controller.rootView = content
        controller.view.invalidateIntrinsicContentSize()
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context) -> CGSize? {
        uiViewController.sizeThatFits(in: CGSize(width: proposal.width ?? UIView.layoutFittingExpandedSize.width,
                                               height: UIView.layoutFittingExpandedSize.height))
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var source: ReorderDragSource
        private var activeSessionID: ObjectIdentifier?

        init(source: ReorderDragSource) {
            self.source = source
        }

        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            [UIDragItem(itemProvider: source.itemProvider)]
        }

        func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
            let sessionID = ObjectIdentifier(session)
            activeSessionID = sessionID
            source.onBegin(sessionID)
        }

        func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem,
                             session: UIDragSession) -> UITargetedDragPreview? {
            guard let view = interaction.view, view.window != nil else { return nil }
            let controller = UIHostingController(rootView: source.preview)
            let previewSize = controller.sizeThatFits(in: view.bounds.size)
            let previewFrame = CGRect(x: view.bounds.midX - previewSize.width / 2,
                                      y: view.bounds.minY,
                                      width: previewSize.width,
                                      height: previewSize.height)

            // Use the rendered tile, including its loaded favicon. A newly created,
            // detached SwiftUI host can be empty when UIKit captures the lift preview.
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(rect: previewFrame)
            return UITargetedDragPreview(view: view, parameters: parameters)
        }

        func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
            let sessionID = ObjectIdentifier(session)
            guard activeSessionID == sessionID else { return }
            activeSessionID = nil
            source.onEnd(sessionID)
        }
    }
}

private struct ReorderDropDelegate<Data: Reorderable>: DropDelegate {

    let data: [Data]
    let item: Data
    let onMove: (_ from: IndexSet, _ to: Int) -> Void
    let onMoveFinished: () -> Void

    @Binding var movedItem: Data?
    @Binding var didMove: Bool

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
            didMove = true
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        movedItem = nil

        if didMove {
            didMove = false
            onMoveFinished()
        }

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
        self.onDragActivityChanged = nil
        self.content = content
        self.preview = nil
        self.onMove = onMove
        self.onMoveFinished = {}
    }

    init(_ data: [Data],
         @ViewBuilder content: @escaping ContentBuilder,
         @ViewBuilder preview: @escaping PreviewBuilder,
         onMove: @escaping (_ from: IndexSet, _ to: Int) -> Void,
         onMoveFinished: @escaping () -> Void) {
        self.data = data
        self.id = \Data.id
        self.isReorderingEnabled = true
        self.onDragActivityChanged = nil
        self.content = content
        self.preview = preview
        self.onMove = onMove
        self.onMoveFinished = onMoveFinished
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
