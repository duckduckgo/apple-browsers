//
//  DaxRig.swift
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

import AppKit
import Lottie

/// Dax's full body, lifted out of the onboarding waving animation, which keeps it in a precomp
/// masked by a backdrop circle.
struct DaxRig {

    /// Frame ranges of the source animation.
    enum Frames {
        /// A step in place that settles on `idle`.
        static let hop: ClosedRange<AnimationFrameTime> = 0...30
        static let idle: AnimationFrameTime = 30
        /// Raises the wing and waves; played backwards to lower it.
        static let wave: ClosedRange<AnimationFrameTime> = 30...58
    }

    /// The part of the canvas Dax ever covers, across every frame, in top-down canvas points.
    static let bodyRect = CGRect(x: 200, y: 30, width: 790, height: 1080)

    /// Midpoint between Dax's eyes at `Frames.idle`, in top-down canvas points.
    static let eyesCenter = CGPoint(x: 590, y: 300)

    static let eyesKeypath = AnimationKeypath(keypath: "Eyes.Transform.Position")
    static let eyesAnchorKeypath = AnimationKeypath(keypath: "Eyes.Transform.Anchor Point")
    static let eyesScaleKeypath = AnimationKeypath(keypath: "Eyes.Transform.Scale")

    /// Pupil centre in the Eyes layer, so blinks squash the eyes in place rather than towards the layer origin.
    static let eyesPivot = CGPoint(x: 8, y: 14)

    let animation: LottieAnimation
    let canvasSize: CGSize
    private let eyesKeyframes: [(frame: CGFloat, position: CGPoint)]

    init?(assetName: String = "dax-waving-light", bundle: Bundle = .main) {
        guard let data = NSDataAsset(name: assetName, bundle: bundle)?.data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["assets"] as? [[String: Any]],
              let body = assets.first(where: { ($0["nm"] as? String) == "Dax_waving_source" }),
              let bodyLayers = body["layers"] as? [[String: Any]],
              let anchor = (root["layers"] as? [[String: Any]])?
                .first(where: { ($0["nm"] as? String) == "Dax_waving_source" })
                .flatMap({ Self.staticValue(of: "a", in: $0) }) else {
            return nil
        }

        var composition = root
        composition["w"] = anchor.x * 2
        composition["h"] = anchor.y * 2
        composition["layers"] = bodyLayers
        composition["assets"] = []
        composition["markers"] = []

        guard let compositionData = try? JSONSerialization.data(withJSONObject: composition),
              let animation = try? LottieAnimation.from(data: compositionData) else {
            return nil
        }
        self.animation = animation
        self.canvasSize = CGSize(width: anchor.x * 2, height: anchor.y * 2)
        self.eyesKeyframes = bodyLayers
            .first(where: { ($0["nm"] as? String) == "Eyes" })
            .map(Self.positionKeyframes(of:)) ?? []
    }

    /// The animated Eyes position at `frame`, linearly interpolated between the source keyframes.
    func eyesPosition(at frame: CGFloat) -> CGPoint {
        guard let first = eyesKeyframes.first, let last = eyesKeyframes.last else { return .zero }
        if frame <= first.frame { return first.position }
        if frame >= last.frame { return last.position }
        let upperIndex = eyesKeyframes.firstIndex { $0.frame > frame } ?? eyesKeyframes.endIndex - 1
        let lower = eyesKeyframes[upperIndex - 1], upper = eyesKeyframes[upperIndex]
        let progress = (frame - lower.frame) / (upper.frame - lower.frame)
        return CGPoint(x: lower.position.x + (upper.position.x - lower.position.x) * progress,
                       y: lower.position.y + (upper.position.y - lower.position.y) * progress)
    }

    private static func staticValue(of property: String, in layer: [String: Any]) -> CGPoint? {
        guard let transform = layer["ks"] as? [String: Any],
              let value = (transform[property] as? [String: Any])?["k"] as? [Double],
              value.count >= 2 else { return nil }
        return CGPoint(x: value[0], y: value[1])
    }

    private static func positionKeyframes(of layer: [String: Any]) -> [(frame: CGFloat, position: CGPoint)] {
        guard let transform = layer["ks"] as? [String: Any],
              let keyframes = (transform["p"] as? [String: Any])?["k"] as? [[String: Any]] else { return [] }
        return keyframes.compactMap { keyframe in
            guard let frame = keyframe["t"] as? Double,
                  let value = keyframe["s"] as? [Double], value.count >= 2 else { return nil }
            return (CGFloat(frame), CGPoint(x: value[0], y: value[1]))
        }
    }
}
