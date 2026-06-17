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

public extension XCTestCase {
    func assertImageSnapshot(
        matching view: NSView,
        strategy: SnapshotImageStrategy = .allAppearances,
        size: SnapshotImageSize,
        record: Bool = false,
        perceptualPrecision: Float = 0.98,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        guard assertSnapshotEnvironment(file: file, line: line) else { return }

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
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    func assertImageSnapshot(
        matching viewController: NSViewController,
        strategy: SnapshotImageStrategy = .allAppearances,
        size: SnapshotImageSize,
        record: Bool = false,
        perceptualPrecision: Float = 0.98,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertImageSnapshot(
            matching: viewController.view,
            strategy: strategy,
            size: size,
            record: record,
            perceptualPrecision: perceptualPrecision,
            file: file,
            testName: testName,
            line: line
        )
    }

    func assertImageSnapshot<Value: SwiftUI.View>(
        matching view: Value,
        strategy: SnapshotImageStrategy = .allAppearances,
        size: SnapshotImageSize,
        record: Bool = false,
        perceptualPrecision: Float = 0.98,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        guard assertSnapshotEnvironment(file: file, line: line) else { return }

        for configuration in strategy.configurations(for: .macOS, size: size) {
            let rootView = view.environment(\.colorScheme, configuration.appearance.colorScheme)
            let viewController = NSHostingController(rootView: rootView)
            let snapshotSize = resolvedSize(
                for: viewController.view,
                configuration: configuration,
                size: size
            )
            viewController.view.setFrameSize(snapshotSize)
            viewController.view.appearance = configuration.appearance.nsAppearance

            assertSnapshot(
                of: viewController.view,
                as: .image(
                    perceptualPrecision: perceptualPrecision,
                    size: snapshotSize
                ),
                named: configuration.name,
                record: SnapshotRecordMode.snapshotTestingRecord(record: record),
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    private func resolvedSize(
        for view: NSView,
        configuration: SnapshotImageConfiguration,
        size: SnapshotImageSize
    ) -> CGSize {
        if let width = size.constrainedWidth {
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
}

private extension SnapshotAppearance {
    var colorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

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
