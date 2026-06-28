//
//  Tool.swift
//  AXION
//
//  Created by Thomas Chamard on 13/05/2026.
//

protocol Tool {
    var name: String { get }
    var requiresConfirmation: Bool { get }

    func execute(argument: String) async -> ToolExecutionResult
}

extension Tool {
    var requiresConfirmation: Bool {
        false
    }
}
