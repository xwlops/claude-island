import Foundation

actor OpenCodeMonitor {
    static let shared = OpenCodeMonitor()

    private let dbPath = NSHomeDirectory() + "/.local/share/opencode/opencode.db"

    private init() {}

    func fetchSessions(limit: Int = 20) async -> [SessionState] {
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let sql = """
        select id, directory, title, time_created, time_updated, time_archived
        from session
        where time_archived is null
        order by time_updated desc
        limit \(limit);
        """

        guard let rows: [OpenCodeSessionRow] = await query(sql) else { return [] }

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
        order by time_created asc;
        """
        let partSql = """
        select
            message_id,
            json_extract(data, '$.type') as type,
            json_extract(data, '$.text') as text,
            json_extract(data, '$.filename') as filename
        from part
        where session_id = '\(escaped(sessionId))'
        order by time_created asc;
        """

        guard let messageRows: [OpenCodeMessageRow] = await query(messageSql) else { return [] }
        let partRows: [OpenCodePartRow] = await query(partSql) ?? []

        var partsByMessageId: [String: [OpenCodePartPayload]] = [:]
        let decoder = JSONDecoder()

        for row in partRows {
            partsByMessageId[row.messageId, default: []].append(
                OpenCodePartPayload(type: row.type, text: row.text, filename: row.filename)
            )
        }

        return messageRows.compactMap { row in
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

        var chatItems: [ChatHistoryItem] = []
        var firstUserMessage: String?
        var lastUserMessageDate: Date?
        var lastMessage: String?
        var lastMessageRole: String?

        for message in messages {
            guard let item = chatItem(from: message) else { continue }
            chatItems.append(item)

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
            case .toolCall, .interrupted:
                break
            }
        }

        let title = row.title.hasPrefix("New session -") ? nil : row.title
        let conversationInfo = ConversationInfo(
            summary: title,
            lastMessage: lastMessage,
            lastMessageRole: lastMessageRole,
            lastToolName: nil,
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
            chatItems: chatItems,
            conversationInfo: conversationInfo,
            lastActivity: updatedAt,
            createdAt: createdAt
        )
    }

    private func chatItem(from message: OpenCodeMessage) -> ChatHistoryItem? {
        let timestamp = date(fromMilliseconds: message.payload.time.created ?? message.timeCreated)
        let content = message.parts.compactMap { part -> String? in
            switch part.type {
            case "text":
                return part.text
            case "file":
                if let filename = part.filename, !filename.isEmpty {
                    return "[Attached file: \(filename)]"
                }
                return "[Attached file]"
            default:
                return nil
            }
        }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")

        switch message.payload.role {
        case "user":
            guard !content.isEmpty else { return nil }
            return ChatHistoryItem(id: message.id, type: .user(content), timestamp: timestamp)
        case "assistant":
            if !content.isEmpty {
                return ChatHistoryItem(id: message.id, type: .assistant(content), timestamp: timestamp)
            }
            if let errorMessage = message.payload.error?.data.message, !errorMessage.isEmpty {
                return ChatHistoryItem(id: message.id, type: .assistant(errorMessage), timestamp: timestamp)
            }
            return nil
        case "system":
            guard !content.isEmpty else { return nil }
            return ChatHistoryItem(id: message.id, type: .thinking(content), timestamp: timestamp)
        default:
            return nil
        }
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
    let title: String
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
    let messageId: String
    let type: String
    let text: String?
    let filename: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case type
        case text
        case filename
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
    let type: String
    let text: String?
    let filename: String?
}
