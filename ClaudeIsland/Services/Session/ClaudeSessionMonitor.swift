//
//  ClaudeSessionMonitor.swift
//  ClaudeIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

@MainActor
class ClaudeSessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()
    private var openCodePollingTask: Task<Void, Never>?

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        HookSocketServer.shared.start(
            onEvent: { event in
                Task {
                    await SessionStore.shared.process(.hookReceived(event))
                }

                if event.sessionPhase == .processing {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.startWatching(
                            sessionId: event.sessionId,
                            cwd: event.cwd
                        )
                    }
                }

                if event.status == "ended" {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                    }
                }

                if event.event == "Stop" {
                    HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                }

                if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )

        Task {
            let claudeSessions = await discoverExistingClaudeSessions()
            await SessionStore.shared.process(
                .providerSessionsUpdated(provider: .claude, sessions: claudeSessions)
            )
        }

        startOpenCodeMonitoring()
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
        openCodePollingTask?.cancel()
        openCodePollingTask = nil
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: reason
            )

            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }

    private func startOpenCodeMonitoring() {
        guard openCodePollingTask == nil else { return }

        openCodePollingTask = Task {
            while !Task.isCancelled {
                let sessions = await OpenCodeMonitor.shared.fetchSessions()
                await SessionStore.shared.process(
                    .providerSessionsUpdated(provider: .opencode, sessions: sessions)
                )

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func discoverExistingClaudeSessions(limit: Int = 20) async -> [SessionState] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var files: [URL] = []
        for projectDir in projectDirs {
            guard let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for file in sessionFiles where file.pathExtension == "jsonl" && !file.lastPathComponent.hasPrefix("agent-") {
                files.append(file)
            }
        }

        let sortedFiles = files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        return sortedFiles.prefix(limit).compactMap { file in
            self.parseClaudeSessionFile(file)
        }
    }

    private func parseClaudeSessionFile(_ file: URL) -> SessionState? {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let sessionId = file.deletingPathExtension().lastPathComponent
        let projectName = file.deletingLastPathComponent().lastPathComponent
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var summary: String?
        var firstUserMessage: String?
        var lastUserMessageDate: Date?
        var lastMessage: String?
        var lastMessageRole: String?
        var lastToolName: String?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = json["type"] as? String
            let isMeta = json["isMeta"] as? Bool ?? false

            if summary == nil, type == "summary", let summaryText = json["summary"] as? String {
                summary = summaryText
            }

            if firstUserMessage == nil,
               type == "user",
               !isMeta,
               let message = json["message"] as? [String: Any],
               let text = message["content"] as? String,
               !text.isEmpty {
                firstUserMessage = compactLine(text, limit: 80)
            }
        }

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = json["type"] as? String
            let isMeta = json["isMeta"] as? Bool ?? false

            if lastMessage == nil,
               (type == "user" || type == "assistant"),
               !isMeta,
               let message = json["message"] as? [String: Any] {
                if let text = message["content"] as? String, !text.isEmpty {
                    lastMessage = compactLine(text, limit: 120)
                    lastMessageRole = type
                } else if let contentArray = message["content"] as? [[String: Any]] {
                    for block in contentArray.reversed() {
                        if block["type"] as? String == "tool_use" {
                            lastToolName = block["name"] as? String
                            lastMessage = compactLine(Self.toolPreview(from: block["input"] as? [String: Any]), limit: 120)
                            lastMessageRole = "tool"
                            break
                        } else if block["type"] as? String == "text", let text = block["text"] as? String, !text.isEmpty {
                            lastMessage = compactLine(text, limit: 120)
                            lastMessageRole = type
                            break
                        }
                    }
                }
            }

            if lastUserMessageDate == nil,
               type == "user",
               let timestamp = json["timestamp"] as? String {
                lastUserMessageDate = formatter.date(from: timestamp)
            }

            if lastMessage != nil && lastUserMessageDate != nil {
                break
            }
        }

        let conversationInfo = ConversationInfo(
            summary: summary,
            lastMessage: lastMessage,
            lastMessageRole: lastMessageRole,
            lastToolName: lastToolName,
            firstUserMessage: firstUserMessage,
            lastUserMessageDate: lastUserMessageDate
        )

        let modifiedAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        return SessionState(
            sessionId: sessionId,
            provider: .claude,
            cwd: projectName,
            projectName: projectName,
            pid: nil,
            tty: nil,
            isInTmux: false,
            phase: lastMessageRole == "user" ? .processing : .waitingForInput,
            chatItems: [],
            conversationInfo: conversationInfo,
            lastActivity: modifiedAt,
            createdAt: modifiedAt
        )
    }

    private func compactLine(_ text: String, limit: Int) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count <= limit {
            return cleaned
        }
        return String(cleaned.prefix(limit)) + "…"
    }

    private static func toolPreview(from input: [String: Any]?) -> String {
        guard let input else { return "" }
        for key in ["description", "command", "pattern", "query", "url", "file_path"] {
            if let value = input[key] as? String, !value.isEmpty {
                return value
            }
        }
        for (_, value) in input {
            if let string = value as? String, !string.isEmpty {
                return string
            }
        }
        return ""
    }
}

// MARK: - Interrupt Watcher Delegate

extension ClaudeSessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}
