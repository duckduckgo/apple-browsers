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
        /// Partway through the wave, the front wing is up beside his face.
        static let wingUp: AnimationFrameTime = 46
    }

    /// Room added above the source canvas, which clips, for a hat to stick out of.
    static let headroom: CGFloat = 160

    /// The part of the canvas Dax ever covers, across every frame, in top-down canvas points.
    static let bodyRect = CGRect(x: 200, y: 30 + headroom, width: 790, height: 1080)

    /// Midpoint between Dax's eyes at `Frames.idle`, in top-down canvas points.
    static let eyesCenter = CGPoint(x: 590, y: 300 + headroom)

    static let eyesKeypath = AnimationKeypath(keypath: "Eyes.Transform.Position")
    static let eyesAnchorKeypath = AnimationKeypath(keypath: "Eyes.Transform.Anchor Point")
    static let eyesScaleKeypath = AnimationKeypath(keypath: "Eyes.Transform.Scale")

    /// Pupil centre in the Eyes layer, so blinks squash the eyes in place rather than towards the layer origin.
    static let eyesPivot = CGPoint(x: 8, y: 14)

    /// The source has two front-wing layers named "Wing-Left"; the one drawn raised, which isn't parented to
    /// Dax, is renamed so it can be posed on its own.
    static let raisedWingLayer = "Wing-Left-Raised"
    static let raisedWingRotationKeypath = AnimationKeypath(keypath: "\(raisedWingLayer).Transform.Rotation")

    static let backWingRotationKeypath = AnimationKeypath(keypath: "Wing-Right.Transform.Rotation")
    static let backWingAnchorKeypath = AnimationKeypath(keypath: "Wing-Right.Transform.Anchor Point")
    static let backWingPositionKeypath = AnimationKeypath(keypath: "Wing-Right.Transform.Position")
    /// Where the back wing joins the body, in its layer, so it flaps from the shoulder.
    static let backWingShoulder = CGPoint(x: -60, y: -40)

    static let hairRotationKeypath = AnimationKeypath(keypath: "Hair.Transform.Rotation")
    static let hairOpacityKeypath = AnimationKeypath(keypath: "Hair.Transform.Opacity")

    /// Each foot is drawn in several layers that lift together.
    static let leftFootLayers = ["Leg-Left", "Foot-Left", "Foot-Left-Stroke", "Foot-Left-Highlight"]
    static let rightFootLayers = ["Leg-Right", "Foot-Right", "Foot-Right-Stroke", "Foot-Right-Highlight"]

    let animation: LottieAnimation
    let canvasSize: CGSize
    let outfit: DaxOutfit?
    /// The back wing's resting place in Dax's layer.
    let backWingPosition: CGPoint
    /// Resting positions of the foot layers, by name.
    let footPositions: [String: CGPoint]
    private let eyesKeyframes: [(frame: CGFloat, position: CGPoint)]
    private let raisedWingKeyframes: [(frame: CGFloat, value: CGFloat)]
    private let hairKeyframes: [(frame: CGFloat, value: CGFloat)]

    init?(assetName: String = "dax-waving-light", bundle: Bundle = .main, outfit: DaxOutfit? = nil) {
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

        // Everything hangs from a null layer that moves it down into the headroom.
        let headroomIndex = 2000
        let headroomLayer: [String: Any] = [
            "ddd": 0, "ind": headroomIndex, "ty": 3, "nm": "Headroom", "sr": 1, "ao": 0, "ip": 0, "op": 1000, "st": 0, "bm": 0,
            "ks": ["o": ["a": 0, "k": 100], "r": ["a": 0, "k": 0], "p": ["a": 0, "k": [0, Self.headroom, 0]],
                   "a": ["a": 0, "k": [0, 0, 0]], "s": ["a": 0, "k": [100, 100, 100]]] as [String: Any]
        ]
        let layers = bodyLayers.map { layer -> [String: Any] in
            var layer = layer
            if (layer["nm"] as? String) == "Wing-Left", layer["parent"] == nil {
                layer["nm"] = Self.raisedWingLayer
            }
            if layer["parent"] == nil {
                layer["parent"] = headroomIndex
            }
            return layer
        }
        func layer(named name: String) -> [String: Any]? {
            layers.first { ($0["nm"] as? String) == name }
        }

        var composition = root
        composition["w"] = anchor.x * 2
        composition["h"] = anchor.y * 2 + Self.headroom
        // Drawn on top of everything, so a hat sits over his head.
        composition["layers"] = (outfit.map { [$0.layer] } ?? []) + layers + [headroomLayer]
        composition["assets"] = []
        composition["markers"] = []

        guard let compositionData = try? JSONSerialization.data(withJSONObject: composition),
              let animation = try? LottieAnimation.from(data: compositionData) else {
            return nil
        }
        self.animation = animation
        self.outfit = outfit
        self.canvasSize = CGSize(width: anchor.x * 2, height: anchor.y * 2 + Self.headroom)
        self.eyesKeyframes = layer(named: "Eyes").map(Self.positionKeyframes(of:)) ?? []
        self.raisedWingKeyframes = layer(named: Self.raisedWingLayer).map { Self.scalarKeyframes(of: "r", in: $0) } ?? []
        self.hairKeyframes = layer(named: "Hair").map { Self.scalarKeyframes(of: "r", in: $0) } ?? []
        self.backWingPosition = layer(named: "Wing-Right").flatMap { Self.staticValue(of: "p", in: $0) } ?? .zero
        self.footPositions = (Self.leftFootLayers + Self.rightFootLayers).reduce(into: [:]) { positions, name in
            positions[name] = layer(named: name).flatMap { Self.staticValue(of: "p", in: $0) }
        }
    }

    /// The raised front wing's animated rotation at `frame`, in degrees.
    func raisedWingRotation(at frame: CGFloat) -> CGFloat {
        Self.interpolate(raisedWingKeyframes, at: frame)
    }

    /// The hair tuft's animated rotation at `frame`, in degrees.
    func hairRotation(at frame: CGFloat) -> CGFloat {
        Self.interpolate(hairKeyframes, at: frame)
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

    private static func interpolate(_ keyframes: [(frame: CGFloat, value: CGFloat)], at frame: CGFloat) -> CGFloat {
        guard let first = keyframes.first, let last = keyframes.last else { return 0 }
        if frame <= first.frame { return first.value }
        if frame >= last.frame { return last.value }
        let upperIndex = keyframes.firstIndex { $0.frame > frame } ?? keyframes.endIndex - 1
        let lower = keyframes[upperIndex - 1], upper = keyframes[upperIndex]
        return lower.value + (upper.value - lower.value) * (frame - lower.frame) / (upper.frame - lower.frame)
    }

    private static func scalarKeyframes(of property: String, in layer: [String: Any]) -> [(frame: CGFloat, value: CGFloat)] {
        guard let transform = layer["ks"] as? [String: Any],
              let keyframes = (transform[property] as? [String: Any])?["k"] as? [[String: Any]] else { return [] }
        return keyframes.compactMap { keyframe in
            guard let frame = keyframe["t"] as? Double, let value = (keyframe["s"] as? [Double])?.first else { return nil }
            return (CGFloat(frame), CGFloat(value))
        }
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
