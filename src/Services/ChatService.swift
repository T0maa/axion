//
//  ChatService.swift
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

import Foundation

final class ChatService {
    private static let modelContextWindowTokens = 4096
    private static let reservedResponseTokens = 160
    private static let reservedMessageOverheadTokens = 96
    private static let estimatedCharactersPerToken = 4.0
    
    private static let systemPrompt = loadSystemPrompt()
    
    private static func loadSystemPrompt() -> String {
        let fallbackPrompt = """
        You are AXION, a concise local macOS agent.
        Return exactly ONE valid compact JSON object.
        If an action is needed, return {"type":"tool_call","category":"CATEGORY","tool":"TOOL_NAME","params":{}}.
        If no action is needed, return {"type":"final","content":"your final answer"}.
        """
        
        let fileManager = FileManager.default
        let resourceURL = Bundle.main.url(forResource: "system_prompt", withExtension: "txt")
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let developmentURL = currentDirectoryURL
            .appendingPathComponent("data/system_prompt.txt")
        let nestedDevelopmentURL = currentDirectoryURL
            .appendingPathComponent("AXION/data/system_prompt.txt")
        let projectURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/AXION/AXION/data/system_prompt.txt")
        
        let candidates = [resourceURL, developmentURL, nestedDevelopmentURL, projectURL].compactMap { $0 }
        
        for url in candidates {
            guard fileManager.fileExists(atPath: url.path),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !trimmedContent.isEmpty {
                return trimmedContent
            }
        }
        
        return fallbackPrompt
    }
    
    func send(messages: [ChatMessage]) async -> String {
        let payload = makePayload(from: messages)
        
        guard let url = URL(string: "http://localhost:8080/v1/chat/completions") else {
            return "Error: invalid local server URL"
        }
        
        let requestBody: [String: Any] = [
            "model": "local",
            "messages": payload,
            "temperature": 0,
            "max_tokens": 160,
            "stream": false
        ]
        
        guard let body = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return "Error: failed to encode conversation"
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown server error"
                return "HTTP \(httpResponse.statusCode): \(errorBody)"
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                let raw = String(data: data, encoding: .utf8) ?? "Unreadable response"
                return "Error: invalid model response: \(raw)"
            }
            
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    func stream(
        messages: [ChatMessage],
        onToken: @escaping (String?) -> Void,
        completion: @escaping () -> Void
    ) {
        Task {
            let response = await send(messages: messages)
            
            if !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onToken(response)
            }
            
            completion()
        }
    }
    
    private func makePayload(from messages: [ChatMessage]) -> [[String: String]] {
        let filteredMessages = messages
            .filter { message in
                message.role == .user || message.role == .assistant || message.role == .tool
            }
            .compactMap { message -> [String: String]? in
                let content = compactContextContent(
                    message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                    role: message.role
                )
                
                guard !content.isEmpty else {
                    return nil
                }
                
                let role = message.role == .assistant ? "assistant" : "user"
                
                return [
                    "role": role,
                    "content": content
                ]
            }
        
        var selectedMessages: [[String: String]] = []
        var currentCharacterCount = 0
        let maxContextCharacters = Self.availableContextCharacters()
        
        for message in filteredMessages.reversed() {
            let content = message["content"] ?? ""
            let messageSize = content.count
            
            if currentCharacterCount + messageSize > maxContextCharacters {
                break
            }
            
            selectedMessages.insert(message, at: 0)
            currentCharacterCount += messageSize
        }
        
        return [
            [
                "role": "system",
                "content": Self.systemPrompt
            ]
        ] + selectedMessages
    }

    private static func availableContextCharacters() -> Int {
        let availableInputTokens = max(
            0,
            modelContextWindowTokens - reservedResponseTokens - reservedMessageOverheadTokens
        )
        let systemPromptTokens = estimatedTokenCount(for: systemPrompt)
        let remainingTokens = max(0, availableInputTokens - systemPromptTokens)
        return Int(Double(remainingTokens) * estimatedCharactersPerToken)
    }

    private static func estimatedTokenCount(for text: String) -> Int {
        Int(ceil(Double(text.count) / estimatedCharactersPerToken))
    }
    
    private func compactContextContent(_ content: String, role: ChatMessage.Role) -> String {
        guard role == .tool else {
            return content
        }
        
        let limit = 1800
        
        guard content.count > limit else {
            return content
        }
        
        return String(content.prefix(limit)) + "\n\n[Context truncated]"
    }
}
