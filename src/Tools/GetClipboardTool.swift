//
//  GetClipboardTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import AppKit

final class GetClipboardTool: Tool {
    let name = "get_clipboard"

    func execute(argument: String) -> String {
        let pasteboard = NSPasteboard.general

        guard let text = pasteboard.string(forType: .string),
              !text.isEmpty else {
            return "Clipboard is empty."
        }

        return "Clipboard content:\n\(text)"
    }
}
