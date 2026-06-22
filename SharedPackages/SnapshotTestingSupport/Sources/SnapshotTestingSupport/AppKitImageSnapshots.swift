//
//  AppKitImageSnapshots.swift
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

#if os(macOS)
import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

public func assertImageSnapshot(
    matching view: NSView,
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
    guard assertSnapshotEnvironment(fileID: fileID, file: file, line: line, column: column) else { return }

    for configuration in strategy.configurations(for: .macOS, size: size) {
        view.appearance = configuration.appearance.nsAppearance
        let snapshotSize = resolvedSize(for: view, configuration: configuration, size: size)

        assertSnapshot(
            of: view,
            as: .image(
                perceptualPrecision: perceptualPrecision,
                size: snapshotSize
            ),
            named: configuration.name,
            record: SnapshotRecordMode.snapshotTestingRecord(record: record),
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column
        )
    }
}

public func assertImageSnapshot(
    matching viewController: NSViewController,
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
    assertImageSnapshot(
        matching: viewController.view,
        strategy: strategy,
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

public func assertImageSnapshot<Value: SwiftUI.View>(
    matching view: Value,
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
    guard assertSnapshotEnvironment(fileID: fileID, file: file, line: line, column: column) else { return }

    for configuration in strategy.configurations(for: .macOS, size: size) {
        let rootView = view.environment(\.colorScheme, configuration.appearance.colorScheme)
        let viewController = NSHostingController(rootView: rootView)
        viewController.view.appearance = configuration.appearance.nsAppearance

        assertSwiftUIImageSnapshot(
            of: viewController,
            configuration: configuration,
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

private func resolvedSize(
    for view: NSView,
    configuration: SnapshotImageConfiguration,
    size: SnapshotImageSize
) -> CGSize {
    if let width = size.fixedConstrainedWidth {
        return constrainedSize(for: view, width: width)
    }

    return size.resolvedSize(
        for: configuration,
        defaultSize: SnapshotDevice.macOSDefaultSize
    ) ?? resolvedSize(for: view)
}

private func resolvedSize(for view: NSView) -> CGSize {
    if view.frame.width > 0, view.frame.height > 0 {
        return view.frame.size
    }

    let fittingSize = view.fittingSize
    if fittingSize.width > 0, fittingSize.height > 0 {
        return fittingSize
    }

    return SnapshotDevice.macOSDefaultSize
}

private func constrainedSize(for view: NSView, width: CGFloat) -> CGSize {
    let originalSize = view.frame.size
    view.setFrameSize(CGSize(width: width, height: 0))
    let fittingHeight = view.fittingSize.height
    view.setFrameSize(originalSize)

    if fittingHeight > 0 {
        return CGSize(width: width, height: fittingHeight)
    }

    return CGSize(width: width, height: SnapshotDevice.macOSDefaultSize.height)
}

private func assertSwiftUIImageSnapshot<Value: SwiftUI.View>(
    of viewController: NSHostingController<Value>,
    configuration: SnapshotImageConfiguration,
    size: SnapshotImageSize,
    record: Bool,
    perceptualPrecision: Float,
    fileID: StaticString,
    file: StaticString,
    testName: String,
    line: UInt,
    column: UInt
) {
    let snapshotSize = swiftUISnapshotSize(
        for: viewController,
        configuration: configuration,
        size: size
    )
    viewController.view.setFrameSize(snapshotSize)

    assertSnapshot(
        of: viewController.view,
        as: .image(
            perceptualPrecision: perceptualPrecision,
            size: snapshotSize
        ),
        named: configuration.name,
        record: SnapshotRecordMode.snapshotTestingRecord(record: record),
        fileID: fileID,
        file: file,
        testName: testName,
        line: line,
        column: column
    )
}

private func swiftUISnapshotSize<Value: SwiftUI.View>(
    for viewController: NSHostingController<Value>,
    configuration: SnapshotImageConfiguration,
    size: SnapshotImageSize
) -> CGSize {
    if let width = size.fixedConstrainedWidth {
        let measuredSize = viewController.sizeThatFits(
            in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )

        if measuredSize.height > 0 {
            return CGSize(width: width, height: measuredSize.height)
        }

        return CGSize(width: width, height: SnapshotDevice.macOSDefaultSize.height)
    }

    if let snapshotSize = size.resolvedSize(
        for: configuration,
        defaultSize: SnapshotDevice.macOSDefaultSize
    ) {
        return snapshotSize
    }

    let measuredSize = viewController.sizeThatFits(
        in: CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    )
    if measuredSize.width > 0, measuredSize.height > 0 {
        return measuredSize
    }

    return resolvedSize(for: viewController.view)
}

private extension SnapshotAppearance {
    var nsAppearance: NSAppearance? {
        let name: NSAppearance.Name
        switch self {
        case .light:
            name = .aqua
        case .dark:
            name = .darkAqua
        }

        return NSAppearance(named: name)
    }
}
#endif
