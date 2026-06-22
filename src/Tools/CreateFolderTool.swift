//
//  CreateFolderTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class CreateFolderTool: Tool {
    let name = "create_folder"

    func execute(argument: String) -> String {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )

            return "Folder created: \(expandedPath)"
        } catch {
            return "Failed to create folder: \(expandedPath)"
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
