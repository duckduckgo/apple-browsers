//
//  UIKitImageSnapshots.swift
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
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

public extension XCTestCase {
    func assertImageSnapshot(
        matching view: UIView,
        strategy: SnapshotImageStrategy = .allAppearances,
        size: SnapshotImageSize,
        record: Bool = false,
        perceptualPrecision: Float = 0.98,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        guard assertSnapshotEnvironment(file: file, line: line) else { return }

        for configuration in strategy.configurations(for: .iOS, size: size) {
            view.overrideUserInterfaceStyle = configuration.appearance.userInterfaceStyle
            let snapshotSize = resolvedSize(for: view, configuration: configuration, size: size)

            assertSnapshot(
                of: view,
                as: .image(
                    drawHierarchyInKeyWindow: false,
                    perceptualPrecision: perceptualPrecision,
                    size: snapshotSize,
                    traits: configuration.appearance.traits
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
        matching viewController: UIViewController,
        strategy: SnapshotImageStrategy = .allAppearances,
        size: SnapshotImageSize,
        record: Bool = false,
        perceptualPrecision: Float = 0.98,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        guard assertSnapshotEnvironment(file: file, line: line) else { return }

        for configuration in strategy.configurations(for: .iOS, size: size) {
            viewController.overrideUserInterfaceStyle = configuration.appearance.userInterfaceStyle
            let snapshotSize = resolvedSize(for: viewController, configuration: configuration, size: size)

            assertSnapshot(
                of: viewController,
                as: .image(
                    drawHierarchyInKeyWindow: false,
                    perceptualPrecision: perceptualPrecision,
                    size: snapshotSize,
                    traits: configuration.appearance.traits
                ),
                named: configuration.name,
                record: SnapshotRecordMode.snapshotTestingRecord(record: record),
                file: file,
                testName: testName,
                line: line
            )
        }
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

        for configuration in strategy.configurations(for: .iOS, size: size) {
            let rootView = view.environment(\.colorScheme, configuration.appearance.colorScheme)
            assertSwiftUIImageSnapshot(
                of: rootView,
                configuration: configuration,
                size: size,
                record: record,
                perceptualPrecision: perceptualPrecision,
                file: file,
                testName: testName,
                line: line
            )
        }
    }
}

private func resolvedSize(
    for view: UIView,
    configuration: SnapshotImageConfiguration,
    size: SnapshotImageSize
) -> CGSize? {
    if let width = size.fixedConstrainedWidth {
        return constrainedSize(for: view, width: width)
    }

    return size.resolvedSize(
        for: configuration,
        defaultSize: SnapshotDevice.iPhoneDefault.size
    ) ?? intrinsicSize(for: view)
}

private func resolvedSize(
    for viewController: UIViewController,
    configuration: SnapshotImageConfiguration,
    size: SnapshotImageSize
) -> CGSize? {
    viewController.loadViewIfNeeded()

    if let width = size.fixedConstrainedWidth {
        return constrainedSize(for: viewController.view, width: width)
    }

    return size.resolvedSize(
        for: configuration,
        defaultSize: SnapshotDevice.iPhoneDefault.size
    ) ?? intrinsicSize(for: viewController.view)
}

private func intrinsicSize(for view: UIView) -> CGSize? {
    view.setNeedsLayout()
    view.layoutIfNeeded()

    if view.intrinsicContentSize.isRenderableSnapshotSize {
        return view.intrinsicContentSize
    }

    let fittingSize = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    if fittingSize.isRenderableSnapshotSize {
        return fittingSize
    }

    if view.frame.size.isRenderableSnapshotSize {
        return view.frame.size
    }

    return nil
}

private func constrainedSize(for view: UIView, width: CGFloat) -> CGSize? {
    view.setNeedsLayout()
    view.layoutIfNeeded()

    let fittingSize = view.systemLayoutSizeFitting(
        CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
    )

    if fittingSize.height.isRenderableSnapshotDimension {
        return CGSize(width: width, height: fittingSize.height)
    }

    if view.frame.height.isRenderableSnapshotDimension {
        return CGSize(width: width, height: view.frame.height)
    }

    return nil
}

private func assertSwiftUIImageSnapshot<Value: SwiftUI.View>(
    of view: Value,
    configuration: SnapshotImageConfiguration,
    size: SnapshotImageSize,
    record: Bool,
    perceptualPrecision: Float,
    file: StaticString,
    testName: String,
    line: UInt
) {
    switch size {
    case .intrinsicContentSize:
        assertSnapshot(
            of: view.fixedSize(),
            as: .image(
                drawHierarchyInKeyWindow: false,
                perceptualPrecision: perceptualPrecision,
                layout: .sizeThatFits,
                traits: configuration.appearance.traits
            ),
            named: configuration.name,
            record: SnapshotRecordMode.snapshotTestingRecord(record: record),
            file: file,
            testName: testName,
            line: line
        )

    case .constrainedWidth:
        assertSnapshot(
            of: view.frame(width: SnapshotDevice.iPhoneDefault.size.width).fixedSize(),
            as: .image(
                drawHierarchyInKeyWindow: false,
                perceptualPrecision: perceptualPrecision,
                layout: .sizeThatFits,
                traits: configuration.appearance.traits
            ),
            named: configuration.name,
            record: SnapshotRecordMode.snapshotTestingRecord(record: record),
            file: file,
            testName: testName,
            line: line
        )

    case .sheet:
        let snapshotSize = size.resolvedSize(
            for: configuration,
            defaultSize: SnapshotDevice.iPhoneDefault.size
        ) ?? SnapshotDevice.iPhoneDefault.size

        assertSnapshot(
            of: SheetSnapshotContainer(
                content: view,
                snapshotSize: snapshotSize,
                isPad: configuration.device == .iPadDefault
            ),
            as: .image(
                drawHierarchyInKeyWindow: false,
                perceptualPrecision: perceptualPrecision,
                layout: .fixed(width: snapshotSize.width, height: snapshotSize.height),
                traits: configuration.appearance.traits
            ),
            named: configuration.name,
            record: SnapshotRecordMode.snapshotTestingRecord(record: record),
            file: file,
            testName: testName,
            line: line
        )

    case .screen, .fixed:
        let snapshotSize = size.resolvedSize(
            for: configuration,
            defaultSize: SnapshotDevice.iPhoneDefault.size
        ) ?? SnapshotDevice.iPhoneDefault.size

        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: false,
                perceptualPrecision: perceptualPrecision,
                layout: .fixed(width: snapshotSize.width, height: snapshotSize.height),
                traits: configuration.appearance.traits
            ),
            named: configuration.name,
            record: SnapshotRecordMode.snapshotTestingRecord(record: record),
            file: file,
            testName: testName,
            line: line
        )
    }
}

private struct SheetSnapshotContainer<Content: SwiftUI.View>: SwiftUI.View {
    let content: Content
    let snapshotSize: CGSize
    let isPad: Bool

    var body: some SwiftUI.View {
        ZStack(alignment: alignment) {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            content
                .frame(width: contentWidth)
                .fixedSize(horizontal: false, vertical: true)
                .clipped()
        }
        .frame(width: snapshotSize.width, height: snapshotSize.height)
    }

    private var alignment: Alignment {
        isPad ? .center : .bottom
    }

    private var contentWidth: CGFloat {
        max(snapshotSize.width - horizontalPadding * 2, 1)
    }

    private var horizontalPadding: CGFloat {
        isPad ? 140 : 0
    }
}

private extension SnapshotAppearance {
    var traits: UITraitCollection {
        UITraitCollection(
            traitsFrom: [
                UITraitCollection(displayScale: CGFloat(SnapshotEnvironment.expectedIOSDisplayScale)),
                UITraitCollection(userInterfaceStyle: userInterfaceStyle)
            ]
        )
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private extension CGSize {
    var isRenderableSnapshotSize: Bool {
        width.isRenderableSnapshotDimension && height.isRenderableSnapshotDimension
    }
}

private extension CGFloat {
    var isRenderableSnapshotDimension: Bool {
        isFinite && self > 0
    }
}
#endif
