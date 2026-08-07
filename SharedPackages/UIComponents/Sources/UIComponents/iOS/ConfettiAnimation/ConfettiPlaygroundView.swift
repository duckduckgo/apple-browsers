//
//  ConfettiPlaygroundView.swift
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

#if os(iOS)

import SwiftUI

/// Harness for tuning ``ConfettiView`` on device without rebuilding.
public struct ConfettiPlaygroundView: View {

    @State private var runID = UUID()

    @State private var particleCount = Double(ConfettiView.Configuration.default.particleCount)
    @State private var startVelocity = ConfettiView.Configuration.default.startVelocity
    @State private var spreadDegrees = ConfettiView.Configuration.default.spreadDegrees
    @State private var gravity = ConfettiView.Configuration.default.gravity
    @State private var decay = ConfettiView.Configuration.default.decay
    @State private var sizeScalar = ConfettiView.Configuration.default.sizeScalar
    @State private var duration = ConfettiView.Configuration.default.duration
    @State private var enabledShapes: Set<ShapeOption> = Set(ShapeOption.allCases)

    public init() {}

    public var body: some View {
        ZStack {
            controls
            ConfettiView(configuration: configuration)
                .id(runID)
        }
        .navigationTitle("Confetti")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Configuration

private extension ConfettiPlaygroundView {

    var configuration: ConfettiView.Configuration {
        .init(particleCount: Int(particleCount),
              startVelocity: startVelocity,
              spreadDegrees: spreadDegrees,
              decay: decay,
              gravity: gravity,
              duration: duration,
              sizeScalar: sizeScalar,
              shapes: shapePool,
                seed: UInt64(truncatingIfNeeded: runID.hashValue))
    }

    var shapePool: [ConfettiShape] {
        let selected = enabledShapes.map(\.shape)
        let pool = ConfettiShape.defaultPool.filter { selected.contains($0) }
        return pool.isEmpty ? ConfettiShape.defaultPool : pool
    }

    enum ShapeOption: String, CaseIterable, Identifiable {
        case star, blob, rect, strip

        var id: Self { self }

        var shape: ConfettiShape {
            switch self {
            case .star: .star
            case .blob: .blob
            case .rect: .rect
            case .strip: .strip
            }
        }
    }
}

// MARK: - Controls

private extension ConfettiPlaygroundView {

    var controls: some View {
        Form {
            Section {
                Button("Replay") { runID = UUID() }
            }

            Section {
                slider("Particles", value: $particleCount, in: 5...200, step: 5, format: "%.0f")
                slider("Start velocity", value: $startVelocity, in: 5...80, step: 1, format: "%.0f")
                slider("Spread", value: $spreadDegrees, in: 10...360, step: 2, format: "%.0f°")
                slider("Gravity", value: $gravity, in: 0...5, step: 0.1, format: "%.1f")
                slider("Decay", value: $decay, in: 0.8...0.99, step: 0.01, format: "%.2f")
                slider("Size", value: $sizeScalar, in: 0.5...8, step: 0.1, format: "%.1f")
                slider("Duration", value: $duration, in: 1...10, step: 0.5, format: "%.1fs")
            } header: {
                Text(verbatim: "Physics")
            }

            Section {
                ForEach(ShapeOption.allCases) { option in
                    Toggle(option.rawValue.capitalized, isOn: binding(for: option))
                }
            } header: {
                Text(verbatim: "Shapes")
            } footer: {
                Text(verbatim: "Turning everything off falls back to the default mix.")
            }
        }
    }

    func slider(_ title: String,
                value: Binding<Double>,
                in range: ClosedRange<Double>,
                step: Double,
                format: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(verbatim: title)
                Spacer()
                Text(verbatim: String(format: format, value.wrappedValue))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    func binding(for option: ShapeOption) -> Binding<Bool> {
        Binding(
            get: { enabledShapes.contains(option) },
            set: { isOn in
                if isOn {
                    enabledShapes.insert(option)
                } else {
                    enabledShapes.remove(option)
                }
            })
    }
}

#endif
