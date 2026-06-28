import Foundation

final class SummarizeTextTool: Tool {
    let name = "summarize_text"

    func execute(argument: String) -> ToolExecutionResult {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .failure(
                title: "Missing text",
                detail: "No text was provided to summarize."
            )
        }

        let summary = makeSimpleSummary(from: trimmed)

        return .success(
            title: "Summary",
            detail: summary
        )
    }

    private func makeSimpleSummary(from text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let sentences = normalized
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.isEmpty {
            return String(normalized.prefix(300))
        }

        let selected = sentences.prefix(3)
        return selected.map { "• \($0)" }.joined(separator: "\n")
    }
}
