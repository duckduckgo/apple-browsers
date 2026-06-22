import UIKit

@MainActor
public protocol DeferredReadingPreviewSession: AnyObject {

    var url: URL { get }
    var previewController: UIViewController { get }

    func openInTab()
    func closeIfNeeded()
}

@MainActor
public protocol DeferredReadingPreviewSessionProviding {

    func makePreviewSession(for url: URL) -> (any DeferredReadingPreviewSession)?
}
