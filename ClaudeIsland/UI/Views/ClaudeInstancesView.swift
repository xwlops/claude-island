//
//  ClaudeInstancesView.swift
//  ClaudeIsland
//
//  Minimal instances list matching Dynamic Island aesthetic
//

import Combine
import SwiftUI

struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @AppStorage("showUsageSummary") private var showUsageSummary: Bool = true

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            instancesList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("No sessions", comment: ""))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text(NSLocalizedString("Run Claude Code or OpenCode in terminal", comment: ""))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        sessionMonitor.instances.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                if showUsageSummary {
                    usageSummary
                }

                ForEach(sortedInstances) { session in
                    InstanceRow(
                        session: session,
                        onFocus: { focusSession(session) },
                        onArchive: { archiveSession(session) },
                        onApprove: { approveSession(session) },
                        onReject: { rejectSession(session) }
                    )
                    .id(session.stableId)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var usageSummary: some View {
        HStack(spacing: 8) {
            UsagePill(label: NSLocalizedString("Sessions", comment: ""), value: "\(sessionMonitor.instances.count)")
            UsagePill(label: NSLocalizedString("Active", comment: ""), value: "\(sessionMonitor.instances.filter { $0.phase == .processing || $0.phase == .compacting }.count)")
            UsagePill(label: NSLocalizedString("Attention", comment: ""), value: "\(sessionMonitor.instances.filter(\.needsAttention).count)")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        guard session.isInTmux else { return }

        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

private struct UsagePill: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 5, height: 5)
            Text(label)
                .foregroundColor(.white.opacity(0.45))
            Text(value)
                .foregroundColor(.white.opacity(0.78))
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false
    @State private var isYabaiAvailable = false

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    private var phaseColor: Color {
        SessionPhaseHelpers.phaseColor(for: session.phase)
    }

    private var relativeTime: String {
        SessionPhaseHelpers.timeAgo(session.lastUserMessageDate ?? session.lastActivity)
    }

    private var providerLabel: String {
        session.provider.displayName
    }

    private var phaseLabel: String {
        switch session.phase {
        case .waitingForApproval:
            return NSLocalizedString("Approve", comment: "")
        case .waitingForInput:
            return NSLocalizedString("Read", comment: "")
        case .processing:
            return NSLocalizedString("Run", comment: "")
        case .compacting:
            return NSLocalizedString("Compact", comment: "")
        case .idle, .ended:
            return NSLocalizedString("Idle", comment: "")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            stateIndicator
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(session.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    rowMetadata
                }

                if isWaitingForApproval, let toolName = session.pendingToolName {
                    HStack(spacing: 4) {
                        Text(MCPToolFormatter.formatToolName(toolName))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(TerminalColors.amber.opacity(0.92))
                        if isInteractiveTool {
                            Text(NSLocalizedString("Needs your input", comment: ""))
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        } else if let input = session.pendingToolInput {
                            Text(input)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                } else if let role = session.lastMessageRole {
                    switch role {
                    case "tool":
                        HStack(spacing: 4) {
                            if let toolName = session.lastToolName {
                                Text(MCPToolFormatter.formatToolName(toolName))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(phaseColor.opacity(0.92))
                            }
                            if let input = session.lastMessage {
                                Text(input)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.58))
                                .lineLimit(1)
                            }
                        }
                    case "user":
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("You:", comment: ""))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.62))
                            if let msg = session.lastMessage {
                                Text(msg)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.58))
                                .lineLimit(1)
                            }
                        }
                    default:
                        if let msg = session.lastMessage {
                            Text(msg)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.58))
                                .lineLimit(1)
                        }
                    }
                } else if let lastMsg = session.lastMessage {
                    Text(lastMsg)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }

                rowActions
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if session.isInTmux && isYabaiAvailable {
                onFocus()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(isHovered ? 0.08 : 0.04), lineWidth: 1)
                )
        )
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    private var rowMetadata: some View {
        HStack(spacing: 6) {
            MetadataPill(label: providerLabel, color: .white.opacity(0.14))
            MetadataPill(label: phaseLabel, color: phaseColor.opacity(0.18), foreground: phaseColor)
            MetadataPill(label: relativeTime, color: .white.opacity(0.08), foreground: .white.opacity(0.66))
        }
    }

    @ViewBuilder
    private var rowActions: some View {
        if isWaitingForApproval {
            HStack(spacing: 8) {
                Button {
                    onReject()
                } label: {
                    Text(NSLocalizedString("Deny", comment: ""))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onApprove()
                } label: {
                    Text(NSLocalizedString("Allow", comment: ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if isYabaiAvailable {
                    TerminalButton(
                        isEnabled: session.isInTmux,
                        onTap: { onFocus() }
                    )
                }
            }
        } else {
            HStack(spacing: 8) {
                if session.isInTmux && isYabaiAvailable {
                    TerminalButton(
                        isEnabled: true,
                        onTap: { onFocus() }
                    )
                }

                if session.phase == .idle || session.phase == .waitingForInput {
                    IconButton(icon: "archivebox") {
                        onArchive()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        HStack(spacing: 3) {
            NotchDragonIcon(size: 13, color: phaseColor, animate: session.phase.isActive)
            NotchFireStatusIcon(size: 10, color: phaseColor, animate: session.phase.needsAttention || session.phase.isActive)
        }
    }

}

private struct MetadataPill: View {
    let label: String
    let color: Color
    var foreground: Color = .white.opacity(0.78)

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color)
            )
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .font(.system(size: 8, weight: .medium))
                Text(NSLocalizedString("Go to Terminal", comment: ""))
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .medium))
                Text(NSLocalizedString("Terminal", comment: ""))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
