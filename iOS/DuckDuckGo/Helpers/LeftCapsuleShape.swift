//
//  LeftCapsuleShape.swift
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

import SwiftUI

/// Capsule-rounded on the left, straight on the right. Used so content sliding off the left
/// pillows against the row's curve while the trailing actions keep their own shape.
struct LeftCapsuleShape: Shape {

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.5
        let arcCenter = CGPoint(x: rect.minX + radius, y: rect.midY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let arcTop = CGPoint(x: arcCenter.x, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)

        return Path { path in
            path.move(to: topRight)
            path.addLine(to: arcTop)
            path.addArc(center: arcCenter, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
            path.addLine(to: bottomRight)
            path.closeSubpath()
        }
    }
}
