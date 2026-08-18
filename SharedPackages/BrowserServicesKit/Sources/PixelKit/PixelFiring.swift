//
//  PixelFiring.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Protocol to support mocking pixel firing.
///
/// This has a single requirement, which is the underlying primitive: fire a pixel and report the
/// outcome through a completion block. Conformers implement only this. The two public entry points,
/// `fire` and `fireAsync`, are extension sugar over it, and neither exposes the completion block to
/// callers.
///
/// The requirement carries an `event:` argument label that the sugar deliberately does not. Keeping
/// the two signatures distinct matters: default argument values are illegal in a protocol
/// requirement, and an extension method whose signature *matches* the requirement silently becomes
/// that requirement's default implementation and calls itself, so a conformer that forgot to
/// implement it would compile cleanly and then recurse forever.
public protocol PixelFiring {
    func fire(event: PixelKit.Event,
              frequency: PixelKit.Frequency,
              options: PixelKit.Options,
              onComplete: @escaping PixelKit.CompletionBlock)
}

extension PixelFiring {

    /// Fires a pixel and returns immediately, without waiting for the request to complete.
    ///
    /// This is the right call for almost every pixel: telemetry should not make the caller wait.
    /// Use `fireAsync` only when the outcome actually matters to the caller.
    public func fire(_ event: PixelKit.Event,
                     frequency: PixelKit.Frequency = .standard,
                     options: PixelKit.Options = .default) {
        fire(event: event, frequency: frequency, options: options, onComplete: { _, _ in })
    }
}

/// `PixelKit` satisfies the requirement with its own `fire(event:frequency:options:onComplete:)`,
/// so no forwarding shim is needed here.
extension PixelKit: PixelFiring {}
