import DeferredReadingCore
import DesignResourcesKit
import SwiftUI

public struct DeferredReadingBannerView: View {

    private let unreadCount: Int
    private let onOpen: () -> Void

    public init(unreadCount: Int, onOpen: @escaping () -> Void) {
        self.unreadCount = unreadCount
        self.onOpen = onOpen
    }

    public var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "globe.badge.clock.fill")
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
                Text(title)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color(designSystemColor: .surface))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if unreadCount == 1 {
            return "1 deferred URL waiting"
        }
        return "\(unreadCount) deferred URLs waiting"
    }
}
