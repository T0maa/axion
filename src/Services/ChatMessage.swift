//
//  ChatMessage.swift
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    var toolResult: ToolExecutionResult?

    init(role: Role, content: String, toolResult: ToolExecutionResult? = nil) {
        self.role = role
        self.content = content
        self.toolResult = toolResult
    }

    var visibleContent: String {
        toolResult?.userMessage ?? content
    }

    enum Role {
        case user
        case assistant
        case tool
    }
}
