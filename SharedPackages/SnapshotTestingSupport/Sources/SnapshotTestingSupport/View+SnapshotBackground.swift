//
//  View+SnapshotBackground.swift
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
import UIKit
#elseif os(macOS)
import AppKit
#endif
import SwiftUI

public extension View {
    func snapshotBackground() -> some View {
        background(SnapshotBackground())
    }
}

private struct SnapshotBackground: View {
    var body: some View {
        backgroundColor
    }

    private var backgroundColor: Color {
        #if os(iOS)
        return Color(uiColor: .systemBackground)
        #elseif os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.clear
        #endif
    }
}

#if os(macOS)
public extension NSView {
    func snapshotBackground() -> NSView {
        SnapshotBackgroundView(content: self)
    }
}

private final class SnapshotBackgroundView: NSView {

    init(content: NSView) {
        super.init(frame: content.frame)
        wantsLayer = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
#endif

#if os(iOS)
public extension UIView {
    func snapshotBackground() -> UIView {
        SnapshotBackgroundView(content: self)
    }
}

private final class SnapshotBackgroundView: UIView {

    init(content: UIView) {
        super.init(frame: content.frame)
        backgroundColor = .systemBackground
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
