//
//  SheetChoiceList.swift
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

#if os(iOS)

import SwiftUI
import DesignResourcesKit

/// One choice in a ``SheetChoiceList``.
public struct SheetChoiceOption: Equatable {
    public let title: String
    public let description: String?

    public init(title: String, description: String? = nil) {
        self.title = title
        self.description = description
    }
}

/// Selection state for a ``SheetChoiceList``. Exactly one option is selected once the user taps one;
/// `selectedIndex` starts at the pre-selected option, if any.
public final class SheetChoiceListViewModel: RadioButtonViewModel {

    private let onSelectionChanged: (Int) -> Void

    /// - Parameters:
    ///   - options: The choices, in display order. The template expects 2 or 3.
    ///   - selectedIndex: The pre-selected option. Out-of-range values select nothing.
    ///   - onSelectionChanged: Called with the new index each time the user selects an option.
    public init(options: [SheetChoiceOption],
                selectedIndex: Int? = 0,
                onSelectionChanged: @escaping (Int) -> Void = { _ in }) {
        let items = options.map { RadioButtonItem(text: $0.title, secondaryText: $0.description) }
        let selectedItem = selectedIndex.flatMap { items.indices.contains($0) ? items[$0] : nil }
        self.onSelectionChanged = onSelectionChanged
        super.init(items: items, selectedItem: selectedItem, configuration: .sheetOption)
    }

    /// The index of the selected option, or `nil` when nothing is selected.
    public var selectedIndex: Int? {
        selectedItem.flatMap { selected in items.firstIndex { $0.id == selected.id } }
    }

    /// Selects the option at `index`. Out-of-range indices are ignored.
    public func select(index: Int) {
        guard items.indices.contains(index) else { return }
        selectItem(items[index])
    }

    public override func selectItem(_ item: RadioButtonItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        super.selectItem(item)
        onSelectionChanged(index)
    }
}

/// Single-select list for choice sheets (Figma `Sheet slot / Choice list`): 2–3 option rows, 8pt apart,
/// with one pre-selected. Built on ``RadioButtonView`` with ``RadioButtonConfiguration/sheetOption``.
public struct SheetChoiceList: View {

    @ObservedObject private var viewModel: SheetChoiceListViewModel

    public init(viewModel: SheetChoiceListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        RadioButtonView(viewModel: viewModel)
    }
}

#if DEBUG

private let previewOptions = [
    SheetChoiceOption(title: "Accept cookies that can't be rejected", description: "Saves you a click on most sites"),
    SheetChoiceOption(title: "I'll keep accepting them myself", description: "Nothing changes"),
]

#Preview("Choice list") {
    SheetChoiceList(viewModel: SheetChoiceListViewModel(options: previewOptions))
        .padding(18)
}

#Preview("Choice list, 3 options, no descriptions, Dark") {
    SheetChoiceList(viewModel: SheetChoiceListViewModel(options: [
        SheetChoiceOption(title: "Accept cookies that can't be rejected"),
        SheetChoiceOption(title: "I'll keep accepting them myself"),
        SheetChoiceOption(title: "Option 3"),
    ]))
    .padding(18)
    .background(Color(designSystemColor: .surfaceTertiary))
    .preferredColorScheme(.dark)
}

#endif

#endif
