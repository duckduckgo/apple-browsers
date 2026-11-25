//
//  SharedDownloads.swift
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

import Foundation

/// The downloads in progress, one per id, each passing its progress to everyone listening. A listener that
/// stops listening leaves the download running, so whoever asks next (a tab, settings) joins it.
actor SharedDownloads {

    typealias Listener = AsyncThrowingStream<Double, Error>.Continuation

    private struct Download {
        /// The latest progress, for listeners that join mid-download.
        var progress: Double?
        var listeners: [UUID: Listener] = [:]
    }

    private var running: [String: Download] = [:]

    /// The download of `id`, joined when one is running and started with `start` otherwise.
    nonisolated func download(_ id: String, start: @escaping @Sendable () -> AsyncThrowingStream<Double, Error>) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { listener in
            Task { await self.join(id, listener, install: start) }
        }
    }

    /// Listens to the pair's download, starting it with `install` when none is running.
    private func join(_ id: String, _ listener: Listener, install: @Sendable () -> AsyncThrowingStream<Double, Error>) {
        if running[id] == nil {
            start(id, install: install)
        }
        add(listener, to: id)
    }

    /// Records the pair's download and starts forwarding its progress.
    private func start(_ id: String, install: @Sendable () -> AsyncThrowingStream<Double, Error>) {
        running[id] = Download()
        let stream = install()
        Task { await forward(stream, for: id) }
    }

    /// Registers a listener, catching it up on the latest progress, and drops it when it stops listening.
    private func add(_ listener: Listener, to id: String) {
        let listenerID = UUID()
        listener.onTermination = { [weak self] _ in
            Task { await self?.remove(listenerID, from: id) }
        }
        if let progress = running[id]?.progress {
            listener.yield(progress)
        }
        running[id]?.listeners[listenerID] = listener
    }

    /// The download keeps running with no one listening, so it's ready when a tab asks again.
    private func remove(_ listenerID: UUID, from id: String) {
        running[id]?.listeners[listenerID] = nil
    }

    /// Passes each progress update of the install to the listeners, then ends the download.
    private func forward(_ stream: AsyncThrowingStream<Double, Error>, for id: String) async {
        do {
            for try await progress in stream {
                send(progress, for: id)
            }
            end(id, throwing: nil)
        } catch {
            end(id, throwing: error)
        }
    }

    /// Keeps the latest progress and passes it to everyone listening.
    private func send(_ progress: Double, for id: String) {
        running[id]?.progress = progress
        running[id]?.listeners.values.forEach { $0.yield(progress) }
    }

    /// Dropped when it ends, so the next call after a failure tries again.
    private func end(_ id: String, throwing error: Error?) {
        let listeners = running.removeValue(forKey: id)?.listeners ?? [:]
        listeners.values.forEach { $0.finish(throwing: error) }
    }
}
