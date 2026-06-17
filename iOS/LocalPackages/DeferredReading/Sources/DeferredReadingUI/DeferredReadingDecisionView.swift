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
        VStack(spacing: 14) {
            Capsule()
                .fill(Color(designSystemColor: .textSecondary).opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Text("Open now or read later?")
                .font(.headline)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(url.host ?? url.absoluteString)
                .font(.footnote)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button("Read Later", action: onDefer)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button("Read Now", action: onReadNow)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color(designSystemColor: .surface))
    }
}
