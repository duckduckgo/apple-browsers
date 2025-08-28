//
//  NewTabPageGridView.swift
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

struct NewTabPageGridView<Content: View>: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @ViewBuilder var content: () -> Content

    var body: some View {
        let columnsCount = NewTabPageGrid.columnsCount(for: horizontalSizeClass)

        LazyVGrid(columns: createColumns(columnsCount), alignment: .center, spacing: 24, content: {
            content()
        })
        .frame(maxWidth: .infinity)
        .padding(0)
    }

    private func createColumns(_ count: Int) -> [GridItem] {
        let isRegularSizeClassOnPad =  UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular

        let spacing: CGFloat = isRegularSizeClassOnPad ? NewTabPageGrid.Item.staticSpacingPad : NewTabPageGrid.Item.staticSpacing
        let maximumSize = NewTabPageGrid.Item.maximumWidth - spacing
        let itemSize = GridItem.Size.flexible(minimum: NewTabPageGrid.Item.edgeSize,
                                          // This causes automatic (larger) spacing, when spacing itself is small comparing to parent view width.
                                              maximum: maximumSize)

        return Array(repeating: GridItem(itemSize, spacing: spacing, alignment: .top),
                     count: count)

    }
}

enum NewTabPageGrid {
    static func columnsCount(for sizeClass: UserInterfaceSizeClass?) -> Int {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        return isPad && sizeClass == .regular ? ColumnCount.staticWideLayout : ColumnCount.compact
    }

    static func staticGridWidth(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let columnsCount = CGFloat(columnsCount(for: sizeClass))
        return columnsCount * Item.edgeSize + (columnsCount - 1) * Item.staticSpacing
    }

    enum Item {
        static let edgeSize = 64.0
    }
}

private extension NewTabPageGrid {
    enum ColumnCount {
        static let compact = 4
        static let staticWideLayout = 5
    }
}

private extension NewTabPageGrid.Item {
    static let staticSpacing = 10.0
    static let staticSpacingPad = 32.0
    static let maximumWidth = 128.0
}
