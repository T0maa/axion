//
//  Untitled.swift
//  AXION
//
//  Created by Thomas Chamard on 23/06/2026.
//

import Foundation

final class OrganizeFolderTool: Tool {
    let name = "organize_folder"

    func execute(argument: String) async -> ToolExecutionResult {
        let parts = argument.split(separator: "|", omittingEmptySubsequences: false)
        let rawPath = parts.indices.contains(0) ? String(parts[0]) : ""
        let mode = parts.indices.contains(1) ? String(parts[1]) : "by_extension"

        let folderURL = URL(fileURLWithPath: expandTilde(rawPath))

        guard mode == "by_extension" else {
            return .failure(title: "Unsupported organize mode", detail: mode)
        }

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failure(title: "Folder does not exist", detail: folderURL.path)
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var movedCount = 0
            var skippedCount = 0
            var results: [String] = []

            for fileURL in files {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])

                if values.isDirectory == true {
                    skippedCount += 1
                    continue
                }

                let category = categoryFor(fileURL)
                let destinationFolder = folderURL.appendingPathComponent(category, isDirectory: true)

                if !FileManager.default.fileExists(atPath: destinationFolder.path) {
                    try FileManager.default.createDirectory(
                        at: destinationFolder,
                        withIntermediateDirectories: true
                    )
                }

                let destinationURL = uniqueDestinationURL(
                    folder: destinationFolder,
                    fileName: fileURL.lastPathComponent
                )

                try FileManager.default.moveItem(at: fileURL, to: destinationURL)

                movedCount += 1
                results.append("\(fileURL.lastPathComponent) -> \(category)/\(destinationURL.lastPathComponent)")
            }

            if results.isEmpty {
                return .neutral(title: "No files to organize", detail: folderURL.path, rawOutput: "No files to organize in \(folderURL.path). Skipped \(skippedCount) folder(s).")
            }

            return .success(
                title: "Organized folder",
                detail: folderURL.path,
                rawOutput: "Organized folder: \(folderURL.path)\nMoved files: \(movedCount)\nSkipped folders: \(skippedCount)\n\n\(results.joined(separator: "\n"))"
            )
        } catch {
            return .failure(title: "Failed to organize folder", detail: error.localizedDescription)
        }
    }

    private func categoryFor(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic":
            return "Images"
        case "pdf":
            return "PDFs"
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            return "Archives"
        case "mp4", "mov", "avi", "mkv", "webm":
            return "Videos"
        case "mp3", "wav", "flac", "aac", "m4a":
            return "Audio"
        case "txt", "md", "doc", "docx", "rtf", "odt":
            return "Documents"
        case "swift", "c", "h", "cpp", "hpp", "py", "js", "ts", "html", "css", "json", "xml", "sh":
            return "Code"
        case "dmg", "pkg", "app":
            return "Installers"
        case "csv", "xls", "xlsx":
            return "Spreadsheets"
        case "ppt", "pptx", "key":
            return "Presentations"
        default:
            return "Other"
        }
    }

    private func uniqueDestinationURL(folder: URL, fileName: String) -> URL {
        let originalURL = folder.appendingPathComponent(fileName)

        if !FileManager.default.fileExists(atPath: originalURL.path) {
            return originalURL
        }

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension

        var index = 1

        while true {
            let newName: String

            if ext.isEmpty {
                newName = "\(baseName)-\(index)"
            } else {
                newName = "\(baseName)-\(index).\(ext)"
            }

            let candidate = folder.appendingPathComponent(newName)

            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }

            index += 1
        }
    }

    private func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}
