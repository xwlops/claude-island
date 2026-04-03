import Foundation

actor OpenCodeMonitor {
    static let shared = OpenCodeMonitor()

    private let dbPath = NSHomeDirectory() + "/.local/share/opencode/opencode.db"

    private init() {}

    func fetchSessions(limit: Int = 8) async -> [SessionState]? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let sql = """
        select id, directory, title, time_created, time_updated, time_archived
        from session
        where time_archived is null
        order by time_updated desc
        limit \(limit);
        """

        guard let rows: [OpenCodeSessionRow] = await query(sql) else { return nil }

        var sessions: [SessionState] = []
        for row in rows {
            let messages = await fetchMessages(for: row.id)
            sessions.append(buildSession(from: row, messages: messages))
        }
        return sessions
    }

    private func fetchMessages(for sessionId: String) async -> [OpenCodeMessage] {
        let messageSql = """
        select id, session_id, time_created, time_updated, data
        from message
        where session_id = '\(escaped(sessionId))'
        order by time_created desc
        limit 80;
        """

        guard let messageRows: [OpenCodeMessageRow] = await query(messageSql), !messageRows.isEmpty else { return [] }

        let sortedMessageRows = messageRows.sorted { $0.timeCreated < $1.timeCreated }
        let messageIds = sortedMessageRows.map(\.id).map { escaped($0) }
        let inClause = messageIds.map { "'\($0)'" }.joined(separator: ",")
        let partSql = """
        select
            id,
            message_id,
            data
        from part
        where session_id = '\(escaped(sessionId))'
          and message_id in (\(inClause))
        order by time_created asc;
        """
        let partRows: [OpenCodePartRow] = await query(partSql) ?? []

        var partsByMessageId: [String: [OpenCodePartPayload]] = [:]
        let decoder = JSONDecoder()

        for row in partRows {
            guard let payload = parsePartPayload(from: row) else { continue }
            partsByMessageId[row.messageId, default: []].append(payload)
        }

        return sortedMessageRows.compactMap { row in
            guard let data = row.data.data(using: .utf8),
                  let payload = try? decoder.decode(OpenCodeMessagePayload.self, from: data) else { return nil }
            return OpenCodeMessage(
                id: row.id,
                timeCreated: row.timeCreated,
                payload: payload,
                parts: partsByMessageId[row.id] ?? []
            )
        }
    }

    private func buildSession(from row: OpenCodeSessionRow, messages: [OpenCodeMessage]) -> SessionState {
        let createdAt = date(fromMilliseconds: row.timeCreated)
        let updatedAt = date(fromMilliseconds: row.timeUpdated)

        var allChatItems: [ChatHistoryItem] = []
        var firstUserMessage: String?
        var lastUserMessageDate: Date?
        var lastMessage: String?
        var lastMessageRole: String?

        for message in messages {
            let items = chatItems(from: message)
            guard !items.isEmpty else { continue }

            for item in items {
                allChatItems.append(item)

                switch item.type {
                case .user(let text):
                    if firstUserMessage == nil && !text.isEmpty {
                        firstUserMessage = text
                    }
                    lastUserMessageDate = item.timestamp
                    lastMessage = text
                    lastMessageRole = "user"
                case .assistant(let text):
                    lastMessage = text
                    lastMessageRole = "assistant"
                case .thinking(let text):
                    lastMessage = text
                    lastMessageRole = "assistant"
                case .toolCall:
                    lastMessageRole = "tool"
                case .interrupted:
                    break
                }
            }
        }

        // Determine lastToolName from the last toolCall item
        var lastToolName: String?
        for item in allChatItems.reversed() {
            if case .toolCall(let tool) = item.type {
                lastToolName = tool.name
                break
            }
        }

        let rawTitle = row.title ?? ""
        let title = rawTitle.hasPrefix("New session -") ? nil : rawTitle
        let conversationInfo = ConversationInfo(
            summary: title,
            lastMessage: lastMessage,
            lastMessageRole: lastMessageRole,
            lastToolName: lastToolName,
            firstUserMessage: firstUserMessage,
            lastUserMessageDate: lastUserMessageDate
        )

        return SessionState(
            sessionId: row.id,
            provider: .opencode,
            cwd: row.directory,
            projectName: URL(fileURLWithPath: row.directory).lastPathComponent,
            pid: nil,
            tty: nil,
            isInTmux: false,
            phase: determinePhase(from: messages.last),
            chatItems: allChatItems,
            conversationInfo: conversationInfo,
            lastActivity: updatedAt,
            createdAt: createdAt
        )
    }

    private func chatItems(from message: OpenCodeMessage) -> [ChatHistoryItem] {
        let timestamp = date(fromMilliseconds: message.payload.time.created ?? message.timeCreated)
        var items: [ChatHistoryItem] = []

        switch message.payload.role {
        case "user":
            let content = message.parts.compactMap(\.displayText).joined(separator: "\n")
            guard !content.isEmpty else { return [] }
            items.append(ChatHistoryItem(id: message.id, type: .user(content), timestamp: timestamp))
        case "assistant":
            for (index, part) in message.parts.enumerated() {
                switch part.type {
                case "reasoning":
                    if let text = part.text?.trimmedForDisplay {
                        items.append(ChatHistoryItem(
                            id: "\(message.id)-reasoning-\(index)",
                            type: .thinking(text),
                            timestamp: timestamp
                        ))
                    }
                case "tool":
                    items.append(ChatHistoryItem(
                        id: part.callID ?? "\(message.id)-tool-\(index)",
                        type: .toolCall(ToolCallItem(
                            name: part.toolName ?? "unknown",
                            input: part.toolInput,
                            status: part.toolStatus,
                            result: part.toolOutput,
                            structuredResult: nil,
                            subagentTools: []
                        )),
                        timestamp: timestamp
                    ))
                case "patch":
                    if let text = part.patchSummary {
                        items.append(ChatHistoryItem(
                            id: "\(message.id)-patch-\(index)",
                            type: .assistant(text),
                            timestamp: timestamp
                        ))
                    }
                default:
                    if let text = part.displayText {
                        items.append(ChatHistoryItem(
                            id: "\(message.id)-\(part.type)-\(index)",
                            type: .assistant(text),
                            timestamp: timestamp
                        ))
                    }
                }
            }
            if items.isEmpty,
               let error = message.payload.error,
               let errorMessage = error.data.message.trimmedForDisplay {
                items.append(ChatHistoryItem(id: message.id, type: .assistant(errorMessage), timestamp: timestamp))
            }
        case "system":
            let content = message.parts.compactMap(\.displayText).joined(separator: "\n")
            guard !content.isEmpty else { return [] }
            items.append(ChatHistoryItem(id: message.id, type: .thinking(content), timestamp: timestamp))
        default:
            return []
        }

        return items
    }

    private func determinePhase(from message: OpenCodeMessage?) -> SessionPhase {
        guard let message else { return .idle }

        if message.payload.role == "user" {
            return .processing
        }

        if message.payload.role == "assistant" && message.payload.time.completed == nil {
            return .processing
        }

        return .waitingForInput
    }

    private func date(fromMilliseconds value: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(value) / 1000)
    }

    private func escaped(_ string: String) -> String {
        string.replacingOccurrences(of: "'", with: "''")
    }

    private func parsePartPayload(from row: OpenCodePartRow) -> OpenCodePartPayload? {
        guard let data = row.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        let text = json["text"] as? String
        let filename = json["filename"] as? String
        let callID = json["callID"] as? String
        let toolName = json["tool"] as? String
        let state = json["state"] as? [String: Any]
        let statusString = state?["status"] as? String
        let input = (state?["input"] as? [String: Any]) ?? [:]
        let output = state?["output"] as? String
        let files = json["files"] as? [String] ?? []

        return OpenCodePartPayload(
            id: row.id,
            type: type,
            text: text,
            filename: filename,
            callID: callID,
            toolName: toolName,
            toolStatus: ToolStatus.from(openCodeStatus: statusString),
            toolInput: normalizeToolInput(input),
            toolOutput: output?.trimmedForDisplay,
            patchFiles: files
        )
    }

    private func normalizeToolInput(_ input: [String: Any]) -> [String: String] {
        var normalized: [String: String] = [:]

        for (key, value) in input {
            switch value {
            case let string as String:
                normalized[key] = string
            case let number as NSNumber:
                normalized[key] = number.stringValue
            case let bool as Bool:
                normalized[key] = bool ? "true" : "false"
            case let array as [String]:
                normalized[key] = array.joined(separator: ", ")
            default:
                continue
            }
        }

        if let filePath = normalized["filePath"], normalized["file_path"] == nil {
            normalized["file_path"] = filePath
        }
        if let description = normalized["description"], normalized["title"] == nil {
            normalized["title"] = description
        }

        return normalized
    }

    private func query<T: Decodable>(_ sql: String) async -> T? {
        do {
            let output = try await ProcessExecutor.shared.run(
                "/usr/bin/sqlite3",
                arguments: ["-json", dbPath, sql]
            )
            guard let data = output.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }
}

private struct OpenCodeSessionRow: Decodable {
    let id: String
    let directory: String
    let title: String?
    let timeCreated: Int64
    let timeUpdated: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case directory
        case title
        case timeCreated = "time_created"
        case timeUpdated = "time_updated"
    }
}

private struct OpenCodeMessageRow: Decodable {
    let id: String
    let sessionId: String
    let timeCreated: Int64
    let data: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case timeCreated = "time_created"
        case data
    }
}

private struct OpenCodePartRow: Decodable {
    let id: String
    let messageId: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case data
    }
}

private struct OpenCodeMessage: Sendable {
    let id: String
    let timeCreated: Int64
    let payload: OpenCodeMessagePayload
    let parts: [OpenCodePartPayload]
}

private struct OpenCodeMessagePayload: Decodable, Sendable {
    let role: String
    let time: OpenCodeMessageTime
    let error: OpenCodeErrorPayload?
}

private struct OpenCodeMessageTime: Decodable, Sendable {
    let created: Int64?
    let completed: Int64?
}

private struct OpenCodeErrorPayload: Decodable, Sendable {
    let data: OpenCodeErrorData
}

private struct OpenCodeErrorData: Decodable, Sendable {
    let message: String
}

private struct OpenCodePartPayload: Sendable {
    let id: String
    let type: String
    let text: String?
    let filename: String?
    let callID: String?
    let toolName: String?
    let toolStatus: ToolStatus
    let toolInput: [String: String]
    let toolOutput: String?
    let patchFiles: [String]

    var displayText: String? {
        switch type {
        case "text", "reasoning":
            return text?.trimmedForDisplay
        case "file":
            if let filename, !filename.isEmpty {
                return "[Attached file: \(filename)]"
            }
            return "[Attached file]"
        default:
            return nil
        }
    }

    var patchSummary: String? {
        guard type == "patch", !patchFiles.isEmpty else { return nil }
        let fileNames = patchFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.prefix(3)
        let suffix = patchFiles.count > 3 ? " +" + String(patchFiles.count - 3) : ""
        return "Updated \(fileNames.joined(separator: ", "))\(suffix)"
    }
}

private extension String {
    var trimmedForDisplay: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ToolStatus {
    static func from(openCodeStatus status: String?) -> ToolStatus {
        switch status {
        case "completed":
            return .success
        case "error", "failed":
            return .error
        case "pending", "running", "in_progress":
            return .running
        default:
            return .running
        }
    }
}
