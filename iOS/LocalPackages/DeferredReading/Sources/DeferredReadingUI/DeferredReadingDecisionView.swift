import DeferredReadingCore
import DesignResourcesKit
import SwiftUI

public struct DeferredReadingDecisionView: View {

    private let url: URL
    private let onReadNow: () -> Void
    private let onDefer: () -> Void

    public init(url: URL,
                onReadNow: @escaping () -> Void,
                onDefer: @escaping () -> Void) {
        self.url = url
        self.onReadNow = onReadNow
        self.onDefer = onDefer
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Read this now?")
                .font(.headline)
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Text(url.host ?? url.absoluteString)
                .font(.subheadline)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)

            Button("Read Now", action: onReadNow)
                .buttonStyle(.borderedProminent)

            Button("Defer to Later", action: onDefer)
                .buttonStyle(.bordered)
        }
        .padding(20)
        .background(Color(designSystemColor: .surface))
    }
}
