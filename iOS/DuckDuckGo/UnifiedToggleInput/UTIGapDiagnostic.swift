//
//  UTIGapDiagnostic.swift
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

import UIKit
import os

/// TEMP diagnostic (uti-host-stable-frame): logs, on every display frame, the UTI bar's bottom Y and
/// the suggestion list's top Y in window coordinates (read from presentation layers, so the values
/// are the true mid-animation positions). Used to confirm the gap between them stays constant during
/// the toggle / focus animation. Remove once the layout is settled.
final class UTIGapDiagnostic {

    private static let logger = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "UTIGap")

    private var link: CADisplayLink?
    private weak var bar: UIView?
    private var listTopProvider: (() -> CGFloat?)?

    func start(bar: UIView, listTopProvider: @escaping () -> CGFloat?) {
        stop()
        self.bar = bar
        self.listTopProvider = listTopProvider
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        bar = nil
        listTopProvider = nil
    }

    @objc private func tick() {
        guard let barBottom = Self.windowMaxY(of: bar), let listTop = listTopProvider?() else { return }
        Self.logger.debug("barBottom=\(barBottom, privacy: .public) listTop=\(listTop, privacy: .public) gap=\(listTop - barBottom, privacy: .public)")
    }

    /// Bottom edge of a view in window coordinates, using its presentation layer so the value reflects
    /// the in-flight animation rather than the settled model frame.
    private static func windowMaxY(of view: UIView?) -> CGFloat? {
        guard let view, let superview = view.superview else { return nil }
        let frame = view.layer.presentation()?.frame ?? view.frame
        return superview.convert(frame, to: nil).maxY
    }
}
