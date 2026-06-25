//
//  ToolExecutionResult.swift
//  AXION
//
//  Created by Thomas Chamard on 23/06/2026.
//

import Foundation


enum ToolExecutionStatus {
    case success
    case warning
    case failure
    case neutral
}

enum ToolExecutionDisplayStyle {
    case compact
    case textBlock
    case codeBlock
    case list
}

struct ToolExecutionResult: ExpressibleByStringLiteral {
    let status: ToolExecutionStatus
    let title: String
    let detail: String
    let rawOutput: String
    let displayStyle: ToolExecutionDisplayStyle

    init(
        status: ToolExecutionStatus,
        title: String,
        detail: String,
        rawOutput: String,
        displayStyle: ToolExecutionDisplayStyle = .compact
    ) {
        self.status = status
        self.title = title
        self.detail = detail
        self.rawOutput = rawOutput
        self.displayStyle = displayStyle
    }

    var userMessage: String {
        if detail.isEmpty {
            return title
        }

        return "\(title): \(detail)"
    }

    static func success(
        title: String,
        detail: String = "",
        rawOutput: String? = nil,
        displayStyle: ToolExecutionDisplayStyle = .compact
    ) -> ToolExecutionResult {
        ToolExecutionResult(
            status: .success,
            title: title,
            detail: detail,
            rawOutput: rawOutput ?? (detail.isEmpty ? title : "\(title): \(detail)"),
            displayStyle: displayStyle
        )
    }

    static func failure(
        title: String,
        detail: String = "",
        rawOutput: String? = nil,
        displayStyle: ToolExecutionDisplayStyle = .compact
    ) -> ToolExecutionResult {
        ToolExecutionResult(
            status: .failure,
            title: title,
            detail: detail,
            rawOutput: rawOutput ?? (detail.isEmpty ? title : "\(title): \(detail)"),
            displayStyle: displayStyle
        )
    }

    static func warning(
        title: String,
        detail: String = "",
        rawOutput: String? = nil,
        displayStyle: ToolExecutionDisplayStyle = .compact
    ) -> ToolExecutionResult {
        ToolExecutionResult(
            status: .warning,
            title: title,
            detail: detail,
            rawOutput: rawOutput ?? (detail.isEmpty ? title : "\(title): \(detail)"),
            displayStyle: displayStyle
        )
    }

    static func neutral(
        title: String,
        detail: String = "",
        rawOutput: String? = nil,
        displayStyle: ToolExecutionDisplayStyle = .compact
    ) -> ToolExecutionResult {
        ToolExecutionResult(
            status: .neutral,
            title: title,
            detail: detail,
            rawOutput: rawOutput ?? (detail.isEmpty ? title : "\(title): \(detail)"),
            displayStyle: displayStyle
        )
    }

    static func legacy(_ message: String) -> ToolExecutionResult {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanMessage.isEmpty else {
            return .neutral(title: "Done")
        }

        let lines = cleanMessage.components(separatedBy: .newlines)
        let headline = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? cleanMessage
        let detail: String

        if lines.count > 1 {
            detail = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let separator = headline.firstIndex(of: ":") {
            detail = headline[headline.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            detail = ""
        }

        let title: String

        if let separator = headline.firstIndex(of: ":") {
            title = String(headline[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            title = headline
        }

        let lowercasedTitle = title.lowercased()
        let lowercasedMessage = cleanMessage.lowercased()
        let status: ToolExecutionStatus

        if lowercasedTitle.hasPrefix("failed")
            || lowercasedTitle.hasPrefix("unable")
            || lowercasedTitle.hasPrefix("invalid")
            || lowercasedTitle.hasPrefix("unsupported")
            || lowercasedTitle.hasPrefix("error")
            || lowercasedMessage.contains("not found")
            || lowercasedMessage.contains("does not exist") {
            status = .failure
        } else if lowercasedTitle.hasPrefix("warning")
            || lowercasedTitle.hasPrefix("confirmation required") {
            status = .warning
        } else {
            status = .success
        }

        return ToolExecutionResult(
            status: status,
            title: title,
            detail: detail,
            rawOutput: cleanMessage,
            displayStyle: Self.inferDisplayStyle(title: title, detail: detail, rawOutput: cleanMessage)
        )
    }

    private static func inferDisplayStyle(title: String, detail: String, rawOutput: String) -> ToolExecutionDisplayStyle {
        let lowercasedTitle = title.lowercased()
        let lowercasedOutput = rawOutput.lowercased()

        if lowercasedTitle.contains("git")
            || lowercasedTitle.contains("process")
            || lowercasedOutput.contains("on branch")
            || lowercasedOutput.contains("pid") {
            return .codeBlock
        }

        if lowercasedTitle.contains("directory")
            || lowercasedTitle.contains("folder content")
            || lowercasedTitle.contains("items") {
            return .list
        }

        if detail.contains("\n") || rawOutput.contains("\n") {
            return .textBlock
        }

        return .compact
    }

    init(stringLiteral value: StringLiteralType) {
        self = .legacy(value)
    }
}
