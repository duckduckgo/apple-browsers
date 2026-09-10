//
//  GraphicLottieRenderer.swift
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

/// App-supplied renderer for ``Graphic/lottie(name:)``.
///
/// `UIComponents` deliberately has no Lottie dependency, so the app injects a renderer (wrapping
/// `Lottie.LottieView`) through the environment. ``GraphicView`` derives the ``GraphicPlayback``
/// and passes it here; the renderer maps it onto Lottie. When no renderer is injected, ``GraphicView``
/// renders nothing for a `.lottie` visual.
public struct GraphicLottieRenderer {
    private let render: (String, GraphicPlayback) -> AnyView

    public init(_ render: @escaping (_ name: String, _ playback: GraphicPlayback) -> AnyView) {
        self.render = render
    }

    func callAsFunction(name: String, playback: GraphicPlayback) -> AnyView {
        render(name, playback)
    }
}

private struct GraphicLottieRendererKey: EnvironmentKey {
    static let defaultValue: GraphicLottieRenderer? = nil
}

public extension EnvironmentValues {
    /// The renderer used to draw ``Graphic/lottie(name:)``. `nil` (the default) makes ``GraphicView``
    /// render nothing for a `.lottie` visual.
    var graphicLottieRenderer: GraphicLottieRenderer? {
        get { self[GraphicLottieRendererKey.self] }
        set { self[GraphicLottieRendererKey.self] = newValue }
    }
}

public extension View {
    /// Injects the renderer used to draw ``Graphic/lottie(name:)`` in this view's subtree.
    func graphicLottieRenderer(_ renderer: GraphicLottieRenderer) -> some View {
        environment(\.graphicLottieRenderer, renderer)
    }
}

#endif
