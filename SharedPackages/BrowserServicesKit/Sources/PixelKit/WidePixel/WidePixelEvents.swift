import Foundation

public enum WidePixelEvents {
    case saveFailed(pixelName: String, error: Error)
    case updateFailed(pixelName: String, error: Error)
    case loadFailed(pixelName: String, error: Error)
    case completeFailed(pixelName: String, error: Error)
}
