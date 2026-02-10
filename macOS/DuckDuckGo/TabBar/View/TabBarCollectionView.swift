//
//  TabBarCollectionView.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Common
import os.log

final class PinnedTabsCollectionView: TabBarCollectionView {

    // Make the view prefer to hug its intrinsic width/height
    override var intrinsicContentSize: NSSize {
        guard let layout = collectionViewLayout else { return .zero }
        layout.invalidateLayout()
        let size = layout.collectionViewContentSize
        // When empty, report zero to collapse
        return numberOfItems(inSection: 0) == 0 ? .zero : size
    }

    override func reloadData() {
        super.reloadData()
        invalidateIntrinsicContentSize()
    }

    override func insertItems(at indexPaths: Set<IndexPath>) {
        super.insertItems(at: indexPaths)
        invalidateIntrinsicContentSize()
    }

    override func deleteItems(at indexPaths: Set<IndexPath>) {
        super.deleteItems(at: indexPaths)
        invalidateIntrinsicContentSize()
    }

    override func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        super.moveItem(at: indexPath, to: newIndexPath)
        invalidateIntrinsicContentSize()
    }
}

open class TabBarCollectionView: NSCollectionView {

    open override var acceptsFirstResponder: Bool {
        return false
    }

    open override func awakeFromNib() {
        super.awakeFromNib()

        register(TabBarViewItem.self, forItemWithIdentifier: TabBarViewItem.identifier)
        register(TabBarFooter.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionFooter, withIdentifier: TabBarFooter.identifier)

        // Register for the dropped object types we can accept.
        registerForDraggedTypes([.URL, .fileURL, TabBarViewItemPasteboardWriter.utiInternalType, .string])
        // Enable dragging items within and into our CollectionView.
        setDraggingSourceOperationMask([.private], forLocal: true)
    }

    open override func selectItems(at indexPaths: Set<IndexPath>, scrollPosition: NSCollectionView.ScrollPosition) {
        super.selectItems(at: indexPaths, scrollPosition: scrollPosition)

        updateItemsLeftToSelectedItems(indexPaths)
    }

    func clearSelection(animated: Bool = false) {
        if animated {
            animator().deselectItems(at: selectionIndexPaths)
        } else {
            deselectItems(at: selectionIndexPaths)
        }
        updateItemsLeftToSelectedItems()
    }

    func scrollToSelected() {
        guard selectionIndexPaths.count == 1, let indexPath = selectionIndexPaths.first else {
            Logger.general.error("TabBarCollectionView: More than 1 item or no item highlighted")
            return
        }
        scroll(to: indexPath)
    }

    func scroll(to indexPath: IndexPath) {
        guard isIndexPathValid(indexPath) else {
            assertionFailure("TabBarCollectionView: Index path out of bounds")
            return
        }
        let rect = frameForItem(at: indexPath.item)
        performAnimatedUpdate { [self] in
            animator().scrollToVisible(rect)
        } completionHandler: { [weak self] didFinish in
            guard let self, didFinish, isIndexPathValid(indexPath) else { return }
            let newRect = frameForItem(at: indexPath.item)
            // make extra pass to make sure the cell is really visible after the animation finishes:
            // in overflown mode the cells are expanded when selected and may get partly hidden
            if rect != newRect, !visibleRect.contains(newRect) {
                self.scroll(to: indexPath)
            }
        }
    }

    func scrollToEnd(completionHandler: ((Bool) -> Void)? = nil) {
        performAnimatedUpdate({
            self.animator().scroll(CGPoint(x: self.bounds.size.width, y: 0))
        }, completionHandler: completionHandler)
    }

    func scrollToBeginning(completionHandler: ((Bool) -> Void)? = nil) {
        performAnimatedUpdate({
            self.animator().scroll(CGPoint(x: 0, y: 0))
        }, completionHandler: completionHandler)
    }

    /// Performs an animated update on the collection view.
    /// On macOS 13+ uses `performBatchUpdates` for proper implicit animations.
    /// On macOS 12 and earlier uses `NSAnimationContext` with explicit layout invalidation
    /// to avoid a crash caused by data source consistency validation in `performBatchUpdates`.
    private func performAnimatedUpdate(_ updates: @escaping () -> Void, completionHandler: ((Bool) -> Void)? = nil) {
        if #available(macOS 13.0, *) {
            animator().performBatchUpdates(updates, completionHandler: completionHandler)
        } else {
            collectionViewLayout?.invalidateLayout()
            NSAnimationContext.runAnimationGroup { _ in
                updates()
            } completionHandler: {
                completionHandler?(true)
            }
        }
    }

    func invalidateLayout() {
        NSAnimationContext.current.duration = 1/3
        collectionViewLayout?.invalidateLayout()
    }

    func isLastItemInSection(indexPath: IndexPath) -> Bool {
        numberOfSections > .zero && indexPath.item == numberOfItems(inSection: indexPath.section) - 1
    }

    func setLastItemSeparatorHidden(_ isHidden: Bool) {
        let numberOfItems = numberOfItems(inSection: 0)
        guard numberOfItems > 0, let item = item(at: numberOfItems-1) as? TabBarViewItem else {
            return
        }
        item.isLeftToSelected = isHidden
    }

    func updateItemsLeftToSelectedItems(_ selectionIndexPaths: Set<IndexPath>? = nil) {
        let indexPaths = selectionIndexPaths ?? self.selectionIndexPaths
        visibleItems().forEach {
            ($0 as? TabBarViewItem)?.isLeftToSelected = false
        }

        for indexPath in indexPaths where indexPath.item > 0 {
            let leftToSelectionIndexPath = IndexPath(item: indexPath.item - 1)
            (item(at: leftToSelectionIndexPath) as? TabBarViewItem)?.isLeftToSelected = true
        }
    }

    func nextItem(for indexPath: IndexPath) -> NSCollectionViewItem? {
        let nextIndexPath = IndexPath(item: indexPath.item + 1, section: indexPath.section)
        return item(at: nextIndexPath)
    }

    func indexPathForItemAtMouseLocation(_ location: NSPoint) -> IndexPath? {
        guard let point = mouseLocationInsideBounds(location), let indexPath = indexPathForItem(at: point) else {
            return nil
        }

        return indexPath
    }

    func tabBarItemAtMouseLocation(_ location: NSPoint) -> TabBarViewItem? {
        guard let indexPath = indexPathForItemAtMouseLocation(location) else {
            return nil
        }

        return item(at: indexPath) as? TabBarViewItem
    }

    // MARK: - Accessibility

    open override func accessibilityChildren() -> [Any]? {
        // matches the internal [NSCollectionViewAccessibilityHelper accessibilityChildren] implementation
        return accessibilityVisibleChildren()
    }

    open override func accessibilityVisibleChildren() -> [Any]? {
        let children = super.accessibilityVisibleChildren()

        // return children from first section (TabBarViewItem-s)
        guard let section = children?.first(where: { ($0 as? NSAccessibilityElement)?.accessibilityRole() == .list }) as? NSAccessibilityElement else { return children }
        var sectionChildren = section.accessibilityVisibleChildren()

        if let footerIndex = sectionChildren?.lastIndex(where: { ($0 as? NSAccessibilityElement)?.accessibilityRole() == .group && ($0 as AnyObject).className.contains("Footer") }) {
            let footer = sectionChildren?.remove(at: footerIndex) as? NSAccessibilityElement
            // move Add Tab button from the Footer to direct Collection View children
            sectionChildren?.append(contentsOf: footer?.accessibilityChildren() ?? [])
        }

        return sectionChildren
    }

    /// prevent NSCollectionView default implementation from returning NSCollectionViewSectionAccessibility object
    open override func accessibilityArrayAttributeValues(_ attribute: NSAccessibility.Attribute, index: Int, maxCount: Int) -> [Any] {
        let values: [Any]
        if case .children = attribute {
            guard let children = accessibilityVisibleChildren(),
                  children.indices.contains(index) else { return [] }
            let range = Range(NSRange(location: index, length: maxCount))!
            let upperBound = min(range.upperBound, children.endIndex)

            values = Array(children[index..<upperBound])
        } else {
            values = super.accessibilityArrayAttributeValues(attribute, index: index, maxCount: maxCount)
        }
        return values
    }

}

extension NSCollectionView {

    var clipView: NSClipView? {
        return enclosingScrollView?.contentView
    }

    var isAtEndScrollPosition: Bool {
        guard let clipView = clipView else {
            Logger.general.error("TabBarCollectionView: Clip view is nil")
            return false
        }

        return clipView.bounds.origin.x + clipView.bounds.size.width >= bounds.size.width
    }

    var isAtStartScrollPosition: Bool {
        guard let clipView = clipView else {
            Logger.general.error("TabBarCollectionView: Clip view is nil")
            return false
        }

        return clipView.bounds.origin.x <= 0
    }

}

extension NSCollectionView {
    func isIndexPathValid(_ indexPath: IndexPath) -> Bool {
        return (0..<numberOfSections).contains(indexPath.section) && (0..<numberOfItems(inSection: indexPath.section)).contains(indexPath.item)
    }
}
