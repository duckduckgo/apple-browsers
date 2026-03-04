//
//  MockNewTabPageOmnibarAiChatsProvider.swift
//  NewTabPage
//
//  Created by Tom on 04/03/2026.
//

import NewTabPage

final class MockNewTabPageOmnibarAiChatsProvider: NewTabPageOmnibarAiChatsProviding {

    var aiChatsHandler: ((String?) async -> NewTabPageDataModel.AiChatsData)?

    @MainActor
    func aiChats(query: String?) async -> NewTabPageDataModel.AiChatsData {
        return await aiChatsHandler?(query) ?? .empty
    }

}
