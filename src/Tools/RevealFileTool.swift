//
//  RevealFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 21/06/2026.
//

import AppKit

final class RevealFileTool: Tool {
    let name = "reveal_file"

    func execute(argument: String) -> ToolExecutionResult {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(title: "File not found", detail: expandedPath)
        }

        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        return .success(title: "Revealed file in Finder", detail: expandedPath)
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
