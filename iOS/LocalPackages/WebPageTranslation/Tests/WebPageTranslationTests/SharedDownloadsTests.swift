//
//  SharedDownloadsTests.swift
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

import Testing
@testable import WebPageTranslation

@Suite
struct SharedDownloadsTests {

    private let downloads = SharedDownloads()
    private let installs = StubInstalls()

    private func download() -> AsyncThrowingStream<Double, Error> {
        let installs = installs
        return downloads.download("es-en") { installs.start() }
    }

    @available(iOS 16, macOS 13, *)
    @Test("two callers share one download, and a late one gets the latest progress at once", .timeLimit(.minutes(1)))
    func concurrentDownloadsShareOne() async {
        let first = ProgressListener()
        let second = ProgressListener()
        let firstListening = first.listen(to: download())
        await waitUntil { installs.count == 1 }
        installs.send(0.5)
        let secondListening = second.listen(to: download())
        await waitUntil { second.fractions == [0.5] }

        installs.send(1)
        installs.finish()
        await firstListening.value
        await secondListening.value

        #expect(installs.count == 1)
        #expect(first.fractions == [0.5, 1])
        #expect(second.fractions == [0.5, 1])
    }

    @available(iOS 16, macOS 13, *)
    @Test("a caller that stops listening doesn't stop the download", .timeLimit(.minutes(1)))
    func abandonedListenerKeepsDownloading() async {
        let first = ProgressListener()
        let second = ProgressListener()
        let firstListening = first.listen(to: download())
        await waitUntil { installs.count == 1 }
        installs.send(0.2)
        let secondListening = second.listen(to: download())
        await waitUntil { second.fractions == [0.2] }

        firstListening.cancel()
        await firstListening.value
        installs.send(1)
        installs.finish()
        await secondListening.value

        #expect(installs.count == 1)
        #expect(!installs.wasCancelled)
        #expect(second.fractions == [0.2, 1])
        #expect(second.ended.map { (try? $0.get()) != nil } == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("a failed download is started again by the next caller", .timeLimit(.minutes(1)))
    func failedDownloadCanRetry() async {
        let failed = ProgressListener()
        let failing = failed.listen(to: download())
        await waitUntil { installs.count == 1 }
        installs.fail()
        await failing.value

        let retried = ProgressListener()
        let retrying = retried.listen(to: download())
        await waitUntil { installs.count == 2 }
        installs.send(1)
        installs.finish()
        await retrying.value

        #expect(failed.ended.map { (try? $0.get()) == nil } == true)
        #expect(retried.fractions == [1])
    }

    @available(iOS 16, macOS 13, *)
    @Test("a download is running from its start until it ends, with or without listeners", .timeLimit(.minutes(1)))
    func runningUntilTheDownloadEnds() async {
        #expect(await !downloads.isRunning("es-en"))
        let listening = ProgressListener().listen(to: download())
        await waitUntil { installs.count == 1 }
        listening.cancel()
        await listening.value
        #expect(await downloads.isRunning("es-en"))

        installs.finish()
        while await downloads.isRunning("es-en"), !Task.isCancelled { await Task.yield() }
    }
}
