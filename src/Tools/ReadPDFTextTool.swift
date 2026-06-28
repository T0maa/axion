//
//  ReadPDFTextTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import Foundation
import PDFKit

final class ReadPDFTextTool: Tool {
    let name = "read_pdf_text"

    func execute(argument: String) async -> ToolExecutionResult {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .failure(title: "PDF not found", detail: expandedPath)
        }

        guard url.pathExtension.lowercased() == "pdf" else {
            return .failure(title: "Not a PDF file", detail: expandedPath)
        }

        guard let document = PDFDocument(url: url) else {
            return .failure(title: "Failed to open PDF", detail: expandedPath)
        }

        var text = ""

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string else {
                continue
            }

            text += "Page \(pageIndex + 1):\n"
            text += pageText
            text += "\n\n"
        }

        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanText.isEmpty {
            return .neutral(title: "No readable text found in PDF", detail: expandedPath)
        }

        if cleanText.count > 12000 {
            return .success(
                title: "PDF text extracted",
                detail: expandedPath,
                rawOutput: String(cleanText.prefix(12000)) + "\n\n[Output truncated]"
            )
        }

        return .success(title: "PDF text extracted", detail: expandedPath, rawOutput: cleanText)
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
