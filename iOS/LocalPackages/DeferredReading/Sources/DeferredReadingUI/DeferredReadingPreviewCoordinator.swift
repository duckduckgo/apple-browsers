import SwiftUI
import UIKit

@MainActor
final class DeferredReadingPreviewCoordinator: ObservableObject {

    private let previewSessionProvider: (any DeferredReadingPreviewSessionProviding)?
    private var activeSession: (any DeferredReadingPreviewSession)?

    init(previewSessionProvider: (any DeferredReadingPreviewSessionProviding)?) {
        self.previewSessionProvider = previewSessionProvider
    }

    func previewSheet(for url: URL) -> DeferredReadingPreviewSheet? {
        guard let previewSessionProvider,
              let session = previewSessionProvider.makePreviewSession(for: url) else {
            return nil
        }

        if let activeSession, activeSession.url != session.url {
            activeSession.closeIfNeeded()
        }

        activeSession = session
        return DeferredReadingPreviewSheet(url: session.url,
                                           previewController: session.previewController)
    }

    func closeActivePreview() {
        activeSession?.closeIfNeeded()
        activeSession = nil
    }

    func openActivePreviewInTab(for url: URL) -> Bool {
        guard let activeSession, activeSession.url == url else {
            return false
        }

        activeSession.openInTab()
        self.activeSession = nil
        return true
    }
}

struct DeferredReadingPreviewSheet: Identifiable {
    let id = UUID()
    let url: URL
    let previewController: UIViewController
}
