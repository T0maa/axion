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

    func execute(argument: String) -> String {
        let path = clean(argument)
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return "PDF not found: \(expandedPath)"
        }

        guard url.pathExtension.lowercased() == "pdf" else {
            return "Not a PDF file: \(expandedPath)"
        }

        guard let document = PDFDocument(url: url) else {
            return "Failed to open PDF: \(expandedPath)"
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
            return "No readable text found in PDF: \(expandedPath)"
        }

        if cleanText.count > 12000 {
            return String(cleanText.prefix(12000)) + "\n\n[Output truncated]"
        }

        return cleanText
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
