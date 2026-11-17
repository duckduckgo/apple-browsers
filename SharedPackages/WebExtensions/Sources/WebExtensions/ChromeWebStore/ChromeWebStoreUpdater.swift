//
//  ChromeWebStoreUpdater.swift
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
import os.log

/// Bounded verification failures, excluding cancellation.
public enum WebExtensionUpdateVerificationFailure: String, Error, CaseIterable, Sendable {
    case invalidPackage = "invalid_package"
    case invalidSignature = "invalid_signature"
    case invalidVersion = "invalid_version"
    case versionMismatch = "version_mismatch"
    case notNewer = "not_newer"
    case storageFailure = "storage_failure"
}

/// Downloads and verifies background updates for installation.
@available(macOS 15.4, iOS 18.4, *)
actor ChromeWebStoreUpdater {
    enum Outcome: Sendable {
        case verified
        case downloadFailed(WebExtensionUpdateDownloadFailure)
        case verificationFailed(WebExtensionUpdateVerificationFailure)
    }

    struct Installation: Equatable, Sendable {
        let identifiers: Set<String>
        let version: String
    }

    typealias InstallationProvider = @MainActor @Sendable (String) -> Installation?
    typealias Download = @Sendable (ChromeWebStoreUpdateChecker.Update) async throws -> Data
    typealias Report = @MainActor @Sendable (String, Outcome) -> Void

    private let download: Download
    private let verifier: ChromeWebStorePackageVerifier
    private let pendingUpdates: any ChromeWebStorePendingUpdateStoring
    private let installation: InstallationProvider
    private let report: Report
    private var active: (update: ChromeWebStoreUpdateChecker.Update, task: Task<Void, Never>)?
    private var isStopped = false

    init(pendingUpdates: any ChromeWebStorePendingUpdateStoring,
         verifier: ChromeWebStorePackageVerifier = .init(),
         download: @escaping Download = { try await ChromeWebStoreUpdateDownloader().download($0) },
         installation: @escaping InstallationProvider,
         report: @escaping Report) {
        self.pendingUpdates = pendingUpdates
        self.verifier = verifier
        self.download = download
        self.installation = installation
        self.report = report
    }

    /// Serializes preparations even across actor suspension points, and joins identical offers.
    func prepare(_ update: ChromeWebStoreUpdateChecker.Update) async {
        while let active {
            await active.task.value
            if active.update == update { return }
        }
        guard !isStopped, !Task.isCancelled else { return }
        let task = Task(priority: .background) {
            await process(update)
            active = nil
        }
        active = (update, task)
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func stop() {
        isStopped = true
        active?.task.cancel()
    }

    private func process(_ update: ChromeWebStoreUpdateChecker.Update) async {
        guard ChromeWebStoreURL.isValidExtensionID(update.extensionID),
              let installed = await installation(update.extensionID), installed.identifiers.count == 1,
              let installationIdentifier = installed.identifiers.first else { return }
        do {
            try Task.checkCancellation()
            if let pending = await pendingUpdates.pendingUpdate(for: update.extensionID),
               !SemanticVersionComparator().isVersion(update.version, newerThan: pending.version) { return }
            let package = try await download(update)
            try Task.checkCancellation()
            // This boundary also protects injected downloaders: metadata is checked before CRX parsing.
            try ChromeWebStoreUpdateDownloader.validate(package, against: update)
            let archive = try verifiedArchive(package, update: update, installedVersion: installed.version)
            try Task.checkCancellation()
            guard await installation(update.extensionID) == installed else { return }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
            var ownsFile = true
            defer {
                if ownsFile { try? FileManager.default.removeItem(at: file) }
            }
            do {
                try archive.data.write(to: file, options: .atomic)
                try Task.checkCancellation()
                let accepted = try await pendingUpdates.store(.init(extensionID: update.extensionID, version: update.version, fileURL: file,
                                                                    installationIdentifier: installationIdentifier))
                ownsFile = !accepted
                try Task.checkCancellation()
                guard accepted else { return }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw WebExtensionUpdateVerificationFailure.storageFailure
            }
            Logger.webExtensions.info("Extension update preparation: \(update.extensionID, privacy: .public) verified")
            await report(update.extensionID, .verified)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if let failure = error as? WebExtensionUpdateVerificationFailure {
                Logger.webExtensions.error("Extension update preparation: \(update.extensionID, privacy: .public) verification failed=\(failure.rawValue, privacy: .public)")
                await report(update.extensionID, .verificationFailed(failure))
            } else {
                let failure = (error as? WebExtensionUpdateDownloadFailure) ?? .networkFailure
                Logger.webExtensions.error("Extension update preparation: \(update.extensionID, privacy: .public) download failed=\(failure.rawValue, privacy: .public)")
                await report(update.extensionID, .downloadFailed(failure))
            }
        }
    }

    private func verifiedArchive(_ package: Data, update: ChromeWebStoreUpdateChecker.Update,
                                 installedVersion: String) throws -> ChromeWebStorePackageVerifier.VerifiedArchive {
        let archive: ChromeWebStorePackageVerifier.VerifiedArchive
        do {
            archive = try verifier.verifiedArchive(in: package, extensionID: update.extensionID)
        } catch ChromeWebStoreError.invalidSignature {
            throw WebExtensionUpdateVerificationFailure.invalidSignature
        } catch {
            throw WebExtensionUpdateVerificationFailure.invalidPackage
        }
        guard let version = archive.version, ChromeWebStoreUpdateChecker.isValidVersion(version),
              ChromeWebStoreUpdateChecker.isValidVersion(update.version), ChromeWebStoreUpdateChecker.isValidVersion(installedVersion) else {
            throw WebExtensionUpdateVerificationFailure.invalidVersion
        }
        guard version == update.version else { throw WebExtensionUpdateVerificationFailure.versionMismatch }
        guard SemanticVersionComparator().isVersion(version, newerThan: installedVersion) else {
            throw WebExtensionUpdateVerificationFailure.notNewer
        }
        return archive
    }
}
