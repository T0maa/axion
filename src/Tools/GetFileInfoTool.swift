//
//  GetFileInfoTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation

final class GetFileInfoTool: Tool {
    let name = "get_file_info"

    func execute(argument: String) -> String {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(
            atPath: expandedPath,
            isDirectory: &isDirectory
        ) else {
            return "Path not found: \(expandedPath)"
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: expandedPath
            )

            let type = isDirectory.boolValue ? "folder" : "file"
            let size = attributes[.size] as? NSNumber
            let modified = attributes[.modificationDate] as? Date

            var lines = [
                "Path: \(expandedPath)",
                "Type: \(type)"
            ]

            if let size {
                lines.append("Size: \(formatBytes(size.intValue))")
            }

            if let modified {
                lines.append("Modified: \(formatDate(modified))")
            }

            lines.append("Name: \(url.lastPathComponent)")

            return "File info:\n" + lines.joined(separator: "\n")
        } catch {
            return "Failed to get file info: \(expandedPath)"
        }
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter.string(from: date)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }

        let kb = Double(bytes) / 1024.0

        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }

        let mb = kb / 1024.0

        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }

        let gb = mb / 1024.0
        return String(format: "%.1f GB", gb)
    }
}
