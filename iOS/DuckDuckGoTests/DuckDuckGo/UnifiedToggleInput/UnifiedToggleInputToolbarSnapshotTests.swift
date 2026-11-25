//
//  UnifiedToggleInputToolbarSnapshotTests.swift
//  DuckDuckGo
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

import AIChat
import SnapshotTestingSupport
import Testing
import UIKit
@testable import DuckDuckGo

/// The prompt box toolbar with the simplified prompt box flag off (today's attach and tools buttons) and on
/// (⊕ only, the tool in a chip with its ✕), at a regular and an SE-size width.
@MainActor
@Suite("Unified Toggle Input Toolbar Snapshot Tests")
final class UnifiedToggleInputToolbarSnapshotTests {

    private static let regularWidth: CGFloat = 390
    private static let narrowWidth: CGFloat = 320

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testFlagOff() {
        assertToolbar(simplified: false, selectedTool: nil, width: Self.regularWidth)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testFlagOffWithWebSearch() {
        assertToolbar(simplified: false, selectedTool: .webSearch, width: Self.regularWidth)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testFlagOn() {
        assertToolbar(simplified: true, selectedTool: nil, width: Self.regularWidth)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testFlagOnWithWebSearch() {
        assertToolbar(simplified: true, selectedTool: .webSearch, width: Self.regularWidth)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testFlagOnWithCreateImageAtNarrowWidth() {
        assertToolbar(simplified: true, selectedTool: .imageGeneration, width: Self.narrowWidth)
    }

    @available(iOS 16, macOS 13, *)
    private func assertToolbar(simplified: Bool,
                               selectedTool: AIChatRAGTool?,
                               width: CGFloat,
                               testName: String = #function) {
        let toolbar = UnifiedToggleInputToolbarView()
        toolbar.backgroundColor = .systemBackground
        toolbar.modelName = "GPT-4o mini"
        toolbar.usesSimplifiedPromptBox = simplified
        // The simplified prompt box has no tools button; the coordinator hides it the same way.
        toolbar.isToolsButtonHidden = simplified
        toolbar.selectedTool = selectedTool

        assertImageSnapshot(
            matching: toolbar,
            size: .fixed(CGSize(width: width, height: 56)),
            testName: testName
        )
    }
}
