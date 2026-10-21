//
//  StubProvider.swift
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

import DuckAIChatCore
import Foundation

/// A provider with no model, for the simulator and tests. Streams `reply` word by word after fake load and read stages.
/// Honours a stop at once, as any provider without an uninterruptible read may.
public final class StubProvider: ChatProvider, @unchecked Sendable {

    public struct Configuration: Sendable {
        public var reply: String
        public var wordsPerSecond: Double
        public var loadTime: Duration
        public var readTime: Duration
        /// Thrown after the first half of `reply` has streamed.
        public var failure: ChatError?
        public var availability: ProviderAvailability

        public init(reply: String = StubProvider.sampleReply,
                    wordsPerSecond: Double = 25,
                    loadTime: Duration = .milliseconds(600),
                    readTime: Duration = .milliseconds(400),
                    failure: ChatError? = nil,
                    availability: ProviderAvailability = .ready) {
            self.reply = reply
            self.wordsPerSecond = wordsPerSecond
            self.loadTime = loadTime
            self.readTime = readTime
            self.failure = failure
            self.availability = availability
        }
    }

    /// Exercises every Markdown block the chat UI renders.
    public static let sampleReply = """
    ## Ducks at a glance

    Ducks are **waterfowl** in the family *Anatidae*. They live on fresh and salt water.

    - Dabbling ducks feed at the surface.
    - Diving ducks swim under water.

    1. Mallard
    2. Teal

    > A duck's feathers are waterproof.

    ```swift
    let duck = Duck(name: "Mallard")
    ```

    | Duck | Habitat |
    | --- | --- |
    | Mallard | Ponds |
    | Eider | Coasts |

    ---

    That is the short version.
    """

    public let descriptor = ProviderDescriptor(id: ProviderID(rawValue: "stub"),
                                               displayName: "Stub",
                                               modelName: "stub",
                                               supportsReasoning: false,
                                               supportsImages: false,
                                               contextWindowTokens: 8_192)

    public init(configuration: Configuration = Configuration()) {
        fatalError("not implemented")
    }

    public var availability: ProviderAvailability {
        fatalError("not implemented")
    }

    public func availabilityUpdates() -> AsyncStream<ProviderAvailability> {
        fatalError("not implemented")
    }

    public func download() async throws {
        fatalError("not implemented")
    }

    public func prepare() async {
        fatalError("not implemented")
    }

    public func unload() {
        fatalError("not implemented")
    }

    public func reply(to turn: ProviderTurn, stop: StopSignal) -> AsyncThrowingStream<ProviderEvent, Error> {
        fatalError("not implemented")
    }
}
