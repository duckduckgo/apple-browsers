import SwiftUI
import UIKit

struct DeferredReadingViewControllerContainer: UIViewControllerRepresentable {

    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}
