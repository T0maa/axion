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

    enum Role {
        case user
        case assistant
        case tool
    }
}
