//
//  GetClipboardTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import AppKit

final class GetClipboardTool: Tool {
    let name = "get_clipboard"

    func execute(argument: String) -> ToolExecutionResult {
        let pasteboard = NSPasteboard.general

        guard let text = pasteboard.string(forType: .string),
              !text.isEmpty else {
            return .neutral(title: "Clipboard is empty")
        }

        let output = "Clipboard content:\n\(text)"

        return .success(
            title: "Clipboard content",
            detail: output,
            rawOutput: output,
            displayStyle: .textBlock
        )    }
}
