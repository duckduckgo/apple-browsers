//
//  NWConnectionExtension.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation
import Network

extension NWConnection {

    var stateUpdateStream: AsyncStream<State> {
        let (stream, continuation) = AsyncStream.makeStream(of: State.self)

        final class ConnectionLifeTimeTracker {
            let continuation: AsyncStream<State>.Continuation
            init(continuation: AsyncStream<State>.Continuation) {
                self.continuation = continuation
            }
            deinit {
                continuation.finish()
            }
        }
        let connectionLifeTimeTracker = ConnectionLifeTimeTracker(continuation: continuation)

        self.stateUpdateHandler = { state in
            withExtendedLifetime(connectionLifeTimeTracker) {
                _=continuation.yield(state)

                switch state {
                case .cancelled, .failed:
                    continuation.finish()
                default: break
                }
            }
        }

        return stream
    }

}
