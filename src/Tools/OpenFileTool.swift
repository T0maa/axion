//
//  OpenFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 08/06/2026.
//

import AppKit

final class OpenFileTool: Tool {
    let name = "open_file"

    func execute(argument: String) async -> ToolExecutionResult {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(title: "File not found", detail: expandedPath)
        }

        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }

        return .success(title: "Opened file", detail: expandedPath)
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
