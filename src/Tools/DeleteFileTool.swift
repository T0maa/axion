//
//  DeleteFileTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation
import AppKit

final class DeleteFileTool: Tool {
    let name = "delete_file"
    let requiresConfirmation = true

    func execute(argument: String) -> String {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return "File not found: \(expandedPath)"
        }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return "File moved to Trash: \(expandedPath)"
        } catch {
            return "Failed to move file to Trash: \(expandedPath)"
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
