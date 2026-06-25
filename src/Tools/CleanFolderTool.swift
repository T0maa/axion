//
//  Untitled.swift
//  AXION
//
//  Created by Thomas Chamard on 23/06/2026.
//

import Foundation
import CryptoKit

final class CleanFolderTool: Tool {
    let name = "clean_folder"

    func execute(argument: String) -> ToolExecutionResult {
        let parts = argument.split(separator: "|", omittingEmptySubsequences: false)
        let rawPath = parts.indices.contains(0) ? String(parts[0]) : ""
        let mode = normalizeMode(parts.indices.contains(1) ? String(parts[1]) : "dry_run")

        let folderURL = URL(fileURLWithPath: expandTilde(rawPath))

        guard mode == "dry_run" || mode == "apply" else {
            return .failure(
                title: "Unsupported clean mode",
                detail: "\(mode). Supported modes: dry_run, apply.",
                displayStyle: .compact
            )
        }

        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failure(title: "Folder does not exist", detail: folderURL.path)
        }

        guard isSafeCleanTarget(folderURL) else {
            return .failure(
                title: "Unsafe clean target",
                detail: "Refusing to clean this folder: \(folderURL.path)",
                displayStyle: .compact
            )
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: []
            )

            var candidates: [(url: URL, reason: String)] = []
            var hashes: [String: URL] = [:]

            for fileURL in files {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])

                if values.isDirectory == true {
                    if isEmptyDirectory(fileURL) {
                        candidates.append((fileURL, "empty folder"))
                    }
                    continue
                }

                let fileName = fileURL.lastPathComponent

                if fileName == "_CleanCandidates" {
                    continue
                }

                if isJunkFile(fileName) {
                    candidates.append((fileURL, "junk file"))
                    continue
                }

                if values.fileSize == 0 {
                    candidates.append((fileURL, "empty file"))
                    continue
                }

                if let hash = sha256(fileURL) {
                    if let original = hashes[hash] {
                        candidates.append((fileURL, "duplicate of \(original.lastPathComponent)"))
                    } else {
                        hashes[hash] = fileURL
                    }
                }
            }

            if candidates.isEmpty {
                return .neutral(
                    title: "No clean candidates found",
                    detail: "Folder: \(folderURL.path)\nNo junk, empty, or duplicate files found.",
                    displayStyle: .textBlock
                )
            }

            if mode == "dry_run" {
                let lines = candidates.map { "\($0.url.lastPathComponent) -> \($0.reason)" }
                let output = "Dry run clean result for: \(folderURL.path)\nCandidates found: \(candidates.count)\nNo files were modified.\n\n\(lines.joined(separator: "\n"))"

                return .success(
                    title: "Dry run clean result",
                    detail: output,
                    rawOutput: output,
                    displayStyle: .textBlock
                )
            }

            let cleanFolder = folderURL.appendingPathComponent("_CleanCandidates", isDirectory: true)

            if !FileManager.default.fileExists(atPath: cleanFolder.path) {
                try FileManager.default.createDirectory(
                    at: cleanFolder,
                    withIntermediateDirectories: true
                )
            }

            var moved: [String] = []

            for candidate in candidates {
                let destinationURL = uniqueDestinationURL(
                    folder: cleanFolder,
                    fileName: candidate.url.lastPathComponent
                )

                try FileManager.default.moveItem(at: candidate.url, to: destinationURL)
                moved.append("\(candidate.url.lastPathComponent) -> _CleanCandidates/\(destinationURL.lastPathComponent) (\(candidate.reason))")
            }

            let output = "Cleaned folder safely: \(folderURL.path)\nMoved candidates: \(moved.count)\nDestination: \(cleanFolder.path)\n\n\(moved.joined(separator: "\n"))"

            return .success(
                title: "Cleaned folder safely",
                detail: output,
                rawOutput: output,
                displayStyle: .textBlock
            )
        } catch {
            return .failure(
                title: "Failed to clean folder",
                detail: error.localizedDescription,
                displayStyle: .textBlock
            )
        }
    }

    private func normalizeMode(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "safe", "apply", "real", "clean", "execute":
            return "apply"
        default:
            return normalized.isEmpty ? "dry_run" : normalized
        }
    }
    
    private func isEmptyDirectory(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return contents.isEmpty
    }

    private func isSafeCleanTarget(_ url: URL) -> Bool {
        let protectedPaths = [
            "/",
            NSHomeDirectory(),
            "/System",
            "/Library",
            "/Applications",
            "/Users",
            "/private",
            "/bin",
            "/sbin",
            "/usr"
        ]

        let standardizedPath = url.standardizedFileURL.path

        return !protectedPaths.contains(standardizedPath)
    }

    private func isJunkFile(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()

        return lower == ".ds_store"
            || lower == "thumbs.db"
            || lower == "desktop.ini"
            || lower.hasSuffix(".tmp")
            || lower.hasSuffix(".temp")
            || lower.hasSuffix(".part")
            || lower.hasSuffix(".crdownload")
            || lower.hasSuffix(".download")
            || lower.hasSuffix("~")
    }

    private func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
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
