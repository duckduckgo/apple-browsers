//
//  NavigationResponseRouterTests.swift
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

import BrowserServicesKit
import Core
import Foundation
import PrivacyConfig
import Testing
@testable import DuckDuckGo

@Suite("NavigationResponseRouter", .serialized)
final class NavigationResponseRouterTests {

    init() {
        PixelFiringMock.tearDown()
    }

    deinit {
        PixelFiringMock.tearDown()
    }

    // MARK: - BLOB (branch 1)

    @available(iOS 16, *)
    @Test("Returns blobAllow when the BLOB already has a temporary download", .timeLimit(.minutes(1)))
    func returnsBlobAllowWhenBlobIsAlreadyPreviewed() {
        // GIVEN
        let router = makeRouter()
        let shape = makeShape(urlSchemeType: .blob, hasTemporaryBlobDownload: true)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .blobAllow)
    }

    @available(iOS 16, *)
    @Test("Returns blobDownload when the BLOB has no temporary download yet", .timeLimit(.minutes(1)))
    func returnsBlobDownloadForFirstTimeBlob() {
        // GIVEN
        let router = makeRouter()
        let shape = makeShape(urlSchemeType: .blob, hasTemporaryBlobDownload: false)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .blobDownload)
    }

    // MARK: - Auto-preview transient (branch 2b)

    @available(iOS 16, *)
    @Test("Returns autoPreviewTransient for pkpass with walletPassDownload on", .timeLimit(.minutes(1)))
    func returnsAutoPreviewTransientForPKPassWithFlagOn() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .passbook)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewTransient)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewTransient for multipass with walletPassDownload on", .timeLimit(.minutes(1)))
    func returnsAutoPreviewTransientForMultipassWithFlagOn() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .multipass)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewTransient)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewTransient for USDZ regardless of walletPassDownload flag", .timeLimit(.minutes(1)))
    func returnsAutoPreviewTransientForUSDZ() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .usdz)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewTransient)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewTransient for octet-stream upgraded to passbook via .pkpass extension", .timeLimit(.minutes(1)))
    func returnsAutoPreviewTransientForOctetStreamWithPkpassExtension() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let upgradedMIME = MIMEType(from: "application/octet-stream", fileExtension: "pkpass")
        let shape = makeShape(
            url: URL(string: "https://example.com/pass.pkpass"),
            mimeType: upgradedMIME,
            suggestedFilename: "pass.pkpass"
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(upgradedMIME == .passbook)
        #expect(decision == .autoPreviewTransient)
    }

    // MARK: - Auto-preview persist (branch 2a)

    @available(iOS 16, *)
    @Test("Returns autoPreviewPersist for pkpass when walletPassDownload is off", .timeLimit(.minutes(1)))
    func returnsAutoPreviewPersistForPKPassWithFlagOff() {
        // GIVEN
        let router = makeRouter(walletPassDownload: false)
        let shape = makeShape(mimeType: .passbook)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewPersist)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewPersist for calendar MIME, even with walletPassDownload also on", .timeLimit(.minutes(1)))
    func returnsAutoPreviewPersistForCalendarMIME() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .calendar)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewPersist)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewPersist for .ics URL extension even when MIME is octet-stream", .timeLimit(.minutes(1)))
    func returnsAutoPreviewPersistForICSByURLExtension() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(
            url: URL(string: "https://example.com/event.ics"),
            mimeType: .octetStream,
            suggestedFilename: "event.ics"
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewPersist)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewPersist for .ics suggestedFilename even when URL has no .ics extension", .timeLimit(.minutes(1)))
    func returnsAutoPreviewPersistForICSBySuggestedFilename() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(
            url: URL(string: "https://example.com/download"),
            mimeType: .octetStream,
            suggestedFilename: "event.ics"
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewPersist)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewPersist for USDZ when walletPassDownload failsafe is off", .timeLimit(.minutes(1)))
    func returnsAutoPreviewPersistForUSDZWhenFlagOff() {
        // GIVEN
        let router = makeRouter(walletPassDownload: false)
        let shape = makeShape(mimeType: .usdz)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewPersist)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewPersist for calendar MIME with a nil URL", .timeLimit(.minutes(1)))
    func returnsAutoPreviewPersistForCalendarWithNilURL() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(url: nil, mimeType: .calendar)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewPersist)
    }

    // MARK: - vCard contact links

    @available(iOS 16, *)
    @Test("Returns autoPreviewPersist for contact MIME, even with walletPassDownload also on", .timeLimit(.minutes(1)))
    func returnsAutoPreviewPersistForContactMIME() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .contact)

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewPersist)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewPersist for .vcf URL extension even when MIME is octet-stream", .timeLimit(.minutes(1)))
    func returnsAutoPreviewPersistForVCardByURLExtension() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(
            url: URL(string: "https://example.com/contact.vcf"),
            mimeType: .octetStream,
            suggestedFilename: "contact.vcf"
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewPersist)
    }

    @available(iOS 16, *)
    @Test("Returns autoPreviewPersist for .vcard suggestedFilename even when URL has no extension", .timeLimit(.minutes(1)))
    func returnsAutoPreviewPersistForVCardBySuggestedFilename() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(
            url: URL(string: "https://example.com/download"),
            mimeType: .octetStream,
            suggestedFilename: "contact.vcard"
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .autoPreviewPersist)
    }

    @available(iOS 16, *)
    @Test("Fires m_download_started with can_auto_preview=1 for a vCard contact", .timeLimit(.minutes(1)))
    func firesDownloadStartedPixelForVCard() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .contact)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        let downloadStarted = PixelFiringMock.allPixelsFired.first { $0.pixelName == Pixel.Event.downloadStarted.name }
        #expect(downloadStarted != nil)
        #expect(downloadStarted?.params?[PixelParameters.canAutoPreviewMIMEType] == "1")
    }

    @available(iOS 16, *)
    @Test("Does not fire wallet_pass_preview_requested for a vCard contact", .timeLimit(.minutes(1)))
    func doesNotFireWalletPassPreviewRequestedForVCard() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .contact)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(!PixelFiringMock.allPixelsFired.contains { $0.pixelName == Pixel.Event.walletPassPreviewRequested.name })
    }

    // MARK: - Data scheme download (branch 3a)

    @available(iOS 16, *)
    @Test("Returns dataSchemeDownload for data: URL when only attachment disposition triggers the download path", .timeLimit(.minutes(1)))
    func returnsDataSchemeDownloadForDataURL() {
        // GIVEN
        // canShowMIMEType true plus .html keeps the canLoadOrPreview clause from also forcing the download,
        // so the attachment flag is the sole trigger and urlNavigationalScheme picks data over userPrompt.
        let router = makeRouter()
        let shape = makeShape(
            url: URL(string: "data:application/pdf;base64,XXX"),
            mimeType: .html,
            canShowMIMEType: true,
            isContentDispositionAttachment: true,
            urlNavigationalScheme: .data
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .dataSchemeDownload)
    }

    // MARK: - User prompt download (branch 3b)

    @available(iOS 16, *)
    @Test("Returns userPromptDownload when Content-Disposition is the only trigger", .timeLimit(.minutes(1)))
    func returnsUserPromptDownloadForAttachmentDisposition() {
        // GIVEN
        // canShowMIMEType true plus .html keeps the canLoadOrPreview clause off, isolating attachment
        // as the only trigger.
        let router = makeRouter()
        let shape = makeShape(
            mimeType: .html,
            canShowMIMEType: true,
            isContentDispositionAttachment: true
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .userPromptDownload)
    }

    @available(iOS 16, *)
    @Test("Returns userPromptDownload when the navigation action download request is the only trigger", .timeLimit(.minutes(1)))
    func returnsUserPromptDownloadForNavigationActionDownload() {
        // GIVEN
        // canShowMIMEType true plus .html keeps the canLoadOrPreview clause off, isolating the
        // navigation-action download request as the only trigger.
        let router = makeRouter()
        let shape = makeShape(
            mimeType: .html,
            canShowMIMEType: true,
            didNavigationActionRequestDownload: true
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .userPromptDownload)
    }

    @available(iOS 16, *)
    @Test("Returns userPromptDownload when MIME cannot be loaded or previewed", .timeLimit(.minutes(1)))
    func returnsUserPromptDownloadForUnloadableMIME() {
        // GIVEN
        let router = makeRouter()
        let shape = makeShape(
            mimeType: .octetStream,
            canShowMIMEType: false
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .userPromptDownload)
    }

    // MARK: - WebView preview (branch 4)

    @available(iOS 16, *)
    @Test("Returns webViewPreview for HTML the webview can render inline", .timeLimit(.minutes(1)))
    func returnsWebViewPreviewForRenderableHTML() {
        // GIVEN
        let router = makeRouter()
        let shape = makeShape(
            mimeType: .html,
            canShowMIMEType: true
        )

        // WHEN
        let decision = router.decide(for: shape)

        // THEN
        #expect(decision == .webViewPreview)
    }

    // MARK: - Pixel firing

    @available(iOS 16, *)
    @Test("Fires m_download_started with can_auto_preview=1 when entering the persist auto-preview branch", .timeLimit(.minutes(1)))
    func firesDownloadStartedPixelOnPersistBranch() {
        // GIVEN
        let router = makeRouter(walletPassDownload: false)
        let shape = makeShape(mimeType: .passbook)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        let downloadStarted = PixelFiringMock.allPixelsFired.first { $0.pixelName == Pixel.Event.downloadStarted.name }
        #expect(downloadStarted != nil)
        #expect(downloadStarted?.params?[PixelParameters.canAutoPreviewMIMEType] == "1")
    }

    @available(iOS 16, *)
    @Test("Fires m_download_started with can_auto_preview=1 when entering the transient auto-preview branch", .timeLimit(.minutes(1)))
    func firesDownloadStartedPixelOnTransientBranch() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .passbook)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        let downloadStarted = PixelFiringMock.allPixelsFired.first { $0.pixelName == Pixel.Event.downloadStarted.name }
        #expect(downloadStarted != nil)
        #expect(downloadStarted?.params?[PixelParameters.canAutoPreviewMIMEType] == "1")
    }

    @available(iOS 16, *)
    @Test("Does not fire a pixel when routing a BLOB", .timeLimit(.minutes(1)))
    func doesNotFirePixelForBlob() {
        // GIVEN
        let router = makeRouter()
        let shape = makeShape(urlSchemeType: .blob, hasTemporaryBlobDownload: false)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Does not fire a pixel when routing to the save-prompt branch", .timeLimit(.minutes(1)))
    func doesNotFirePixelForUserPromptDownload() {
        // GIVEN
        let router = makeRouter()
        let shape = makeShape(
            mimeType: .octetStream,
            canShowMIMEType: false,
            isContentDispositionAttachment: true
        )

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Does not fire a pixel when routing to webViewPreview", .timeLimit(.minutes(1)))
    func doesNotFirePixelForWebViewPreview() {
        // GIVEN
        let router = makeRouter()
        let shape = makeShape(mimeType: .html, canShowMIMEType: true)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.isEmpty)
    }

    // MARK: - Wallet pass preview pixel

    @available(iOS 16, *)
    @Test("Fires wallet_pass_preview_requested for pkpass on the transient branch", .timeLimit(.minutes(1)))
    func firesWalletPassPreviewRequestedForPKPassTransient() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .passbook)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.contains { $0.pixelName == Pixel.Event.walletPassPreviewRequested.name })
    }

    @available(iOS 16, *)
    @Test("Fires wallet_pass_preview_requested for pkpass on the persist branch", .timeLimit(.minutes(1)))
    func firesWalletPassPreviewRequestedForPKPassPersist() {
        // GIVEN
        let router = makeRouter(walletPassDownload: false)
        let shape = makeShape(mimeType: .passbook)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.contains { $0.pixelName == Pixel.Event.walletPassPreviewRequested.name })
    }

    @available(iOS 16, *)
    @Test("Fires wallet_pass_preview_requested for multipass", .timeLimit(.minutes(1)))
    func firesWalletPassPreviewRequestedForMultipass() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .multipass)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(PixelFiringMock.allPixelsFired.contains { $0.pixelName == Pixel.Event.walletPassPreviewRequested.name })
    }

    @available(iOS 16, *)
    @Test("Does not fire wallet_pass_preview_requested for USDZ", .timeLimit(.minutes(1)))
    func doesNotFireWalletPassPreviewRequestedForUSDZ() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .usdz)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(!PixelFiringMock.allPixelsFired.contains { $0.pixelName == Pixel.Event.walletPassPreviewRequested.name })
    }

    @available(iOS 16, *)
    @Test("Does not fire wallet_pass_preview_requested for ICS", .timeLimit(.minutes(1)))
    func doesNotFireWalletPassPreviewRequestedForICS() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(mimeType: .calendar)

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(!PixelFiringMock.allPixelsFired.contains { $0.pixelName == Pixel.Event.walletPassPreviewRequested.name })
    }

    @available(iOS 16, *)
    @Test("Does not fire wallet_pass_preview_requested for ICS routed via URL extension", .timeLimit(.minutes(1)))
    func doesNotFireWalletPassPreviewRequestedForICSByURLExtension() {
        // GIVEN
        let router = makeRouter(walletPassDownload: true)
        let shape = makeShape(
            url: URL(string: "https://example.com/event.ics"),
            mimeType: .octetStream,
            suggestedFilename: "event.ics"
        )

        // WHEN
        _ = router.decide(for: shape)

        // THEN
        #expect(!PixelFiringMock.allPixelsFired.contains { $0.pixelName == Pixel.Event.walletPassPreviewRequested.name })
    }

    // MARK: - Helpers

    private func makeRouter(walletPassDownload: Bool = true) -> NavigationResponseRouter {
        var enabled: [FeatureFlag] = []
        if walletPassDownload { enabled.append(.walletPassDownload) }
        let flagger = MockFeatureFlagger(enabledFeatureFlags: enabled)
        return NavigationResponseRouter(featureFlagger: flagger, pixelFiring: PixelFiringMock.self)
    }

    private func makeShape(
        url: URL? = URL(string: "https://example.com/file"),
        mimeType: MIMEType = .unknown,
        canShowMIMEType: Bool = false,
        suggestedFilename: String? = nil,
        isContentDispositionAttachment: Bool = false,
        didNavigationActionRequestDownload: Bool = false,
        urlSchemeType: SchemeHandler.SchemeType = .navigational,
        urlNavigationalScheme: URL.NavigationalScheme? = .https,
        hasTemporaryBlobDownload: Bool = false
    ) -> NavigationResponseRouter.ResponseShape {
        NavigationResponseRouter.ResponseShape(
            url: url,
            mimeType: mimeType,
            canShowMIMEType: canShowMIMEType,
            suggestedFilename: suggestedFilename,
            isContentDispositionAttachment: isContentDispositionAttachment,
            didNavigationActionRequestDownload: didNavigationActionRequestDownload,
            urlSchemeType: urlSchemeType,
            urlNavigationalScheme: urlNavigationalScheme,
            hasTemporaryBlobDownload: hasTemporaryBlobDownload
        )
    }
}
