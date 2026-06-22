//
//  CopyToClipboard.swift
//  AXION
//
//  Created by Thomas Chamard on 21/06/2026.
//

import AppKit

final class CopyToClipboardTool: Tool {
    let name = "copy_to_clipboard"

    func execute(argument: String) -> String {
        let text = argument.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            return "No text to copy"
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        return "Text copied in the clipboard."
    }
}
