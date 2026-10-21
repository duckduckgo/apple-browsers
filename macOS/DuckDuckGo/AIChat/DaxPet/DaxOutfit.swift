//
//  DaxOutfit.swift
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

import CoreGraphics
import Foundation

/// Something for Dax to wear, drawn as an extra layer of his rig that moves with him.
enum DaxOutfit: String, CaseIterable {
    case witchHat
    case santaHat
    case partyHat

    var title: String {
        switch self {
        case .witchHat: return UserText.daxPetOutfitWitchHat
        case .santaHat: return UserText.daxPetOutfitSantaHat
        case .partyHat: return UserText.daxPetOutfitPartyHat
        }
    }

    /// Halloween week, December, and New Year's Eve into New Year's Day.
    static func seasonal(on date: Date, calendar: Calendar = .current) -> DaxOutfit? {
        let day = calendar.dateComponents([.month, .day], from: date)
        switch (day.month, day.day) {
        case (10, .some(24...31)): return .witchHat
        case (12, .some(31)), (1, .some(1)): return .partyHat
        case (12, _): return .santaHat
        default: return nil
        }
    }

    /// Hats hide the hair tuft they sit on.
    var hidesHair: Bool { true }

    /// A shape layer parented to Dax, in his layer's coordinates, where the top of his head is around
    /// (104, -589).
    var layer: [String: Any] {
        let shapes: [[String: Any]]
        switch self {
        case .witchHat: shapes = Self.witchHatShapes
        case .santaHat: shapes = Self.santaHatShapes
        case .partyHat: shapes = Self.partyHatShapes
        }
        return [
            "ddd": 0, "ind": 1000, "ty": 4, "nm": "Outfit", "parent": 1, "sr": 1, "ao": 0,
            "ip": 0, "op": 1000, "st": 0, "bm": 0,
            "ks": Shape.transform(),
            "shapes": shapes
        ]
    }

    // MARK: - Hats

    private static let ink = (r: 0.0, g: 0.0, b: 0.0)

    private static var witchHatShapes: [[String: Any]] {
        let purple = (r: 0.29, g: 0.23, b: 0.42), orange = (r: 0.97, g: 0.64, b: 0.11)
        return [Shape.group(rotation: -8, pivot: CGPoint(x: 112, y: -585), [
            // Band, cone and brim, front to back.
            Shape.group([
                Shape.path([CGPoint(x: 52, y: -612), CGPoint(x: 176, y: -610), CGPoint(x: 172, y: -642), CGPoint(x: 58, y: -645)]),
                Shape.stroke(ink), Shape.fill(orange)
            ]),
            Shape.group([
                Shape.path([CGPoint(x: 44, y: -598), CGPoint(x: 40, y: -870), CGPoint(x: 186, y: -596)],
                           inTangents: [.zero, CGPoint(x: 0, y: 0), CGPoint(x: -20, y: -120)],
                           outTangents: [CGPoint(x: 30, y: -110), CGPoint(x: 40, y: 60), .zero]),
                Shape.stroke(ink), Shape.fill(purple)
            ]),
            Shape.group([Shape.ellipse(center: CGPoint(x: 114, y: -590), size: CGSize(width: 270, height: 46)), Shape.stroke(ink), Shape.fill(purple)])
        ])]
    }

    private static var santaHatShapes: [[String: Any]] {
        let red = (r: 0.85, g: 0.2, b: 0.17), white = (r: 1.0, g: 1.0, b: 1.0)
        return [Shape.group([
            Shape.group([Shape.ellipse(center: CGPoint(x: -52, y: -650), size: CGSize(width: 64, height: 64)), Shape.stroke(ink), Shape.fill(white)]),
            Shape.group([Shape.rectangle(center: CGPoint(x: 114, y: -592), size: CGSize(width: 184, height: 46), roundness: 23),
                         Shape.stroke(ink), Shape.fill(white)]),
            Shape.group([
                Shape.path([CGPoint(x: 34, y: -608), CGPoint(x: -48, y: -650), CGPoint(x: 120, y: -770), CGPoint(x: 196, y: -612)],
                           inTangents: [.zero, CGPoint(x: -10, y: 30), CGPoint(x: -110, y: -10), CGPoint(x: 10, y: -80)],
                           outTangents: [CGPoint(x: -30, y: -10), CGPoint(x: 20, y: -80), CGPoint(x: 70, y: 10), .zero]),
                Shape.stroke(ink), Shape.fill(red)
            ])
        ])]
    }

    private static var partyHatShapes: [[String: Any]] {
        let blue = (r: 0.22, g: 0.41, b: 0.94), yellow = (r: 1.0, g: 0.84, b: 0.36), coral = (r: 0.87, g: 0.35, b: 0.2)
        let dots = [CGPoint(x: 100, y: -630), CGPoint(x: 135, y: -680), CGPoint(x: 92, y: -720), CGPoint(x: 124, y: -770)].map {
            Shape.group([Shape.ellipse(center: $0, size: CGSize(width: 20, height: 20)), Shape.fill(yellow)])
        }
        return [Shape.group(rotation: 12, pivot: CGPoint(x: 112, y: -590), [
            Shape.group([Shape.ellipse(center: CGPoint(x: 112, y: -830), size: CGSize(width: 44, height: 44)), Shape.stroke(ink), Shape.fill(coral)])
        ] + dots + [
            Shape.group([
                Shape.path([CGPoint(x: 52, y: -596), CGPoint(x: 112, y: -820), CGPoint(x: 172, y: -596)],
                           inTangents: [CGPoint(x: 0, y: 0), .zero, .zero],
                           outTangents: [.zero, .zero, CGPoint(x: -30, y: 12)]),
                Shape.stroke(ink), Shape.fill(blue)
            ])
        ])]
    }
}

/// Wardrobe choice: dressed for the season, never dressed, or always one outfit.
enum DaxWardrobe: Equatable {
    case seasonal
    case none
    case outfit(DaxOutfit)

    init(rawValue: String?) {
        switch rawValue {
        case "none": self = .none
        case let value?: self = DaxOutfit(rawValue: value).map(DaxWardrobe.outfit) ?? .seasonal
        default: self = .seasonal
        }
    }

    var rawValue: String {
        switch self {
        case .seasonal: return "seasonal"
        case .none: return "none"
        case .outfit(let outfit): return outfit.rawValue
        }
    }

    func outfit(on date: Date, calendar: Calendar = .current) -> DaxOutfit? {
        switch self {
        case .seasonal: return DaxOutfit.seasonal(on: date, calendar: calendar)
        case .none: return nil
        case .outfit(let outfit): return outfit
        }
    }
}

/// Just enough Lottie shape JSON to draw outfits.
private enum Shape {

    static func transform(rotation: CGFloat = 0, pivot: CGPoint = .zero) -> [String: Any] {
        [
            "o": ["a": 0, "k": 100], "r": ["a": 0, "k": rotation],
            "p": ["a": 0, "k": [pivot.x, pivot.y, 0]], "a": ["a": 0, "k": [pivot.x, pivot.y, 0]],
            "s": ["a": 0, "k": [100, 100, 100]]
        ]
    }

    static func group(rotation: CGFloat = 0, pivot: CGPoint = .zero, _ items: [[String: Any]]) -> [String: Any] {
        var groupTransform = transform(rotation: rotation, pivot: pivot)
        groupTransform["ty"] = "tr"
        return ["ty": "gr", "it": items + [groupTransform]]
    }

    /// A closed path; tangents are relative to their vertex.
    static func path(_ vertices: [CGPoint], inTangents: [CGPoint]? = nil, outTangents: [CGPoint]? = nil) -> [String: Any] {
        let zeros = vertices.map { _ in CGPoint.zero }
        func pairs(_ points: [CGPoint]) -> [[CGFloat]] { points.map { [$0.x, $0.y] } }
        return ["ty": "sh", "ks": ["a": 0, "k": [
            "c": true, "v": pairs(vertices), "i": pairs(inTangents ?? zeros), "o": pairs(outTangents ?? zeros)
        ] as [String: Any]]]
    }

    static func ellipse(center: CGPoint, size: CGSize) -> [String: Any] {
        ["ty": "el", "p": ["a": 0, "k": [center.x, center.y]], "s": ["a": 0, "k": [size.width, size.height]]]
    }

    static func rectangle(center: CGPoint, size: CGSize, roundness: CGFloat) -> [String: Any] {
        ["ty": "rc", "p": ["a": 0, "k": [center.x, center.y]], "s": ["a": 0, "k": [size.width, size.height]], "r": ["a": 0, "k": roundness]]
    }

    static func fill(_ color: (r: Double, g: Double, b: Double)) -> [String: Any] {
        ["ty": "fl", "c": ["a": 0, "k": [color.r, color.g, color.b, 1]], "o": ["a": 0, "k": 100], "r": 1]
    }

    static func stroke(_ color: (r: Double, g: Double, b: Double)) -> [String: Any] {
        ["ty": "st", "c": ["a": 0, "k": [color.r, color.g, color.b, 1]], "o": ["a": 0, "k": 100], "w": ["a": 0, "k": 4], "lc": 2, "lj": 2]
    }
}
