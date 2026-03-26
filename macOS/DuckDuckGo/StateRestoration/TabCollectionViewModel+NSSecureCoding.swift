//
//  TabCollectionViewModel+NSSecureCoding.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

extension TabCollectionViewModel: NSSecureCoding {
    private enum NSSecureCodingKeys {
        static let tabCollection = "tabs"
        static let selectionIndex = "idx"
    }

    static var supportsSecureCoding: Bool { true }

    convenience init?(coder: NSCoder) {
        guard let tabCollection = coder.decodeObject(of: TabCollection.self, forKey: NSSecureCodingKeys.tabCollection) else {
            return nil
        }
        let index = coder.decodeIfPresent(at: NSSecureCodingKeys.selectionIndex) ?? 0
        // Burner tabs aren't stored
        let burnerMode = BurnerMode.regular
        self.init(tabCollection: tabCollection,
                  selectionIndex: .unpinned(index),
                  burnerMode: burnerMode)

        // The selected tab was decoded as .suspended — materialize it now so it has a webView.
        // selectUnpinnedTab (called via selectionIndex didSet) handles materialization,
        // but during init the didSet doesn't fire (Swift behavior), so we do it explicitly.
        if case .suspended = tabCollection.tabs[safe: index] {
            materialize(at: .unpinned(index))
        }
    }

    func encode(with coder: NSCoder) {
        if case let .unpinned(index) = selectionIndex {
            coder.encode(index, forKey: NSSecureCodingKeys.selectionIndex)
        }
        coder.encode(tabCollection, forKey: NSSecureCodingKeys.tabCollection)
    }

}
