//
//  AssertPreviewSnapshots.swift
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

import PreviewSnapshots
import SwiftUI

public func assertImageSnapshots<State>(
    _ previews: PreviewSnapshots<State>,
    strategy: SnapshotImageStrategy = .allAppearances,
    size: SnapshotImageSize,
    record: Bool = false,
    perceptualPrecision: Float = 0.98,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    assertImageSnapshots(
        previews,
        strategy: { _ in strategy },
        size: size,
        record: record,
        perceptualPrecision: perceptualPrecision,
        fileID: fileID,
        file: file,
        testName: testName,
        line: line,
        column: column
    )
}

public func assertImageSnapshots<State>(
    _ previews: PreviewSnapshots<State>,
    strategy: (State) -> SnapshotImageStrategy,
    size: SnapshotImageSize,
    record: Bool = false,
    perceptualPrecision: Float = 0.98,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    for configuration in previews.snapshotConfigurations {
        assertImageSnapshot(
            matching: previews.configure(configuration.state),
            strategy: namedStrategy(
                strategy(configuration.state),
                previewName: configuration.name,
                size: size
            ),
            size: size,
            record: record,
            perceptualPrecision: perceptualPrecision,
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column
        )
    }
}

private func namedStrategy(
    _ strategy: SnapshotImageStrategy,
    previewName: String,
    size: SnapshotImageSize
) -> SnapshotImageStrategy {
    .custom(
        strategy.configurationsForCurrentPlatform(size: size).map {
            SnapshotImageConfiguration(
                appearance: $0.appearance,
                device: $0.device,
                name: SnapshotNameGenerator.name(
                    forPreview: previewName,
                    snapshotName: $0.name
                ),
                size: $0.size
            )
        }
    )
}

private extension SnapshotImageStrategy {
    func configurationsForCurrentPlatform(size: SnapshotImageSize) -> [SnapshotImageConfiguration] {
        #if os(iOS)
        return configurations(for: .iOS, size: size)
        #elseif os(macOS)
        return configurations(for: .macOS, size: size)
        #else
        return []
        #endif
    }
}
