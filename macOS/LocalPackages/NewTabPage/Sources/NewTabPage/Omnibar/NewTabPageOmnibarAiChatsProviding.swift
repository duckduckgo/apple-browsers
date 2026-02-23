//
//  NewTabPageOmnibarAiChatsProviding.swift
//  NewTabPage
//
//  Created by Tom on 23/02/2026.
//

public protocol NewTabPageOmnibarAiChatsProviding: AnyObject {

    @MainActor
    func aiChats() async -> NewTabPageDataModel.AiChatsData

}
