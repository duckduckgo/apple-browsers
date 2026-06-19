import SwiftUI
import UIKit

@MainActor
public final class DeferredReadingPromptState: ObservableObject {

    @Published public private(set) var title: String?
    @Published public private(set) var urlText: String
    @Published public private(set) var favicon: UIImage?
    @Published public private(set) var currentURL: URL

    public init(initialURL: URL) {
        currentURL = initialURL
        urlText = initialURL.absoluteString
    }

    public func updatePage(title: String?, url: URL) {
        self.title = title
        currentURL = url
        urlText = url.absoluteString
    }

    public func updateFavicon(_ image: UIImage?) {
        favicon = image
    }
}

public struct DeferredReadingPromptSheetView: View {

    @ObservedObject var state: DeferredReadingPromptState

    let onReadNow: () -> Void
    let onReadLater: () -> Void
    let onPauseForToday: () -> Void
    let onDisappear: () -> Void

    public init(state: DeferredReadingPromptState,
                onReadNow: @escaping () -> Void,
                onReadLater: @escaping () -> Void,
                onPauseForToday: @escaping () -> Void,
                onDisappear: @escaping () -> Void = {}) {
        self.state = state
        self.onReadNow = onReadNow
        self.onReadLater = onReadLater
        self.onPauseForToday = onPauseForToday
        self.onDisappear = onDisappear
    }

    public var body: some View {
        VStack(spacing: 16) {
            header
                .padding(.top, 6)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button(action: onReadLater) {
                    Text("Read Later")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onPauseForToday) {
                    Text("Pause for Today")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onReadNow) {
                    Text("Read Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .onDisappear(perform: onDisappear)
    }

    private var header: some View {
        HStack(spacing: 10) {
            faviconView
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title ?? state.currentURL.host ?? state.urlText)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                Text(state.urlText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if let favicon = state.favicon {
            Image(uiImage: favicon)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .padding(4)
                .foregroundStyle(.secondary)
        }
    }
}
