//
//  NotchView.swift
//  ClaudeIsland
//
//  The main dynamic island SwiftUI view with accurate notch shape
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(4), bottom: CGFloat(10))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @StateObject private var sessionMonitor = ClaudeSessionMonitor()
    @StateObject private var activityCoordinator = NotchActivityCoordinator.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var previousPendingIds: Set<String> = []
    @State private var previousWaitingForInputIds: Set<String> = []
    @State private var waitingForInputTimestamps: [String: Date] = [:]  // sessionId -> when it entered waitingForInput
    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false
    @State private var isBouncing: Bool = false
    @State private var isBehaviorHidden: Bool = false
    @State private var isClosedStatusPulsing: Bool = false

    private let visibilityTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    @Namespace private var activityNamespace

    /// Whether any Claude session is currently processing or compacting
    private var isAnyProcessing: Bool {
        sessionMonitor.instances.contains { $0.phase == .processing || $0.phase == .compacting }
    }

    /// Whether any Claude session has a pending permission request
    private var hasPendingPermission: Bool {
        sessionMonitor.instances.contains { $0.phase.isWaitingForApproval }
    }

    /// Whether any Claude session is waiting for user input (done/ready state) within the display window
    private var hasWaitingForInput: Bool {
        let now = Date()
        let displayDuration: TimeInterval = 30  // Show checkmark for 30 seconds

        return sessionMonitor.instances.contains { session in
            guard session.phase == .waitingForInput else { return false }
            // Only show if within the 30-second display window
            if let enteredAt = waitingForInputTimestamps[session.stableId] {
                return now.timeIntervalSince(enteredAt) < displayDuration
            }
            return false
        }
    }

    // MARK: - Sizing

    private var closedNotchHeight: CGFloat {
        20
    }

    private var closedMaximumWidth: CGFloat {
        max(148, viewModel.deviceNotchRect.width * 0.62)
    }

    private var closedNotchSize: CGSize {
        return CGSize(
            width: closedMaximumWidth,
            height: closedNotchHeight
        )
    }

    /// Extra width for expanding activities (like Dynamic Island)
    private var expansionWidth: CGFloat {
        // Permission indicator adds width on left side only
        let permissionIndicatorWidth: CGFloat = hasPendingPermission ? 18 : 0

        // Expand for processing activity
        if activityCoordinator.expandingActivity.show {
            switch activityCoordinator.expandingActivity.type {
            case .claude:
                let baseWidth = 2 * max(0, closedNotchSize.height - 12) + 20
                return baseWidth + permissionIndicatorWidth
            case .none:
                break
            }
        }

        // Expand for pending permissions (left indicator) or waiting for input (checkmark on right)
        if hasPendingPermission {
            return 2 * max(0, closedNotchSize.height - 12) + 20 + permissionIndicatorWidth
        }

        // Waiting for input just shows checkmark on right, no extra left indicator
        if hasWaitingForInput {
            return 2 * max(0, closedNotchSize.height - 12) + 20
        }

        return 0
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return closedNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    // MARK: - Corner Radii

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    // Animation springs
    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container does NOT receive hits - only the notch content does
            VStack(spacing: 0) {
                notchLayout
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        maxHeight: viewModel.status == .opened ? notchSize.height : nil,
                        alignment: .top
                    )
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
                    .animation(openAnimation, value: notchSize) // Animate container size changes between content types
                    .animation(.smooth, value: activityCoordinator.expandingActivity)
                    .animation(.smooth, value: hasPendingPermission)
                    .animation(.smooth, value: hasWaitingForInput)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isBouncing)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }
                    }
                    .onTapGesture {
                        if viewModel.status != .opened {
                            viewModel.notchOpen(reason: .click)
                        }
                    }
            }
        }
        .opacity(isVisible && !isBehaviorHidden ? 1 : 0)
        .allowsHitTesting(isVisible && !isBehaviorHidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            sessionMonitor.startMonitoring()
            isClosedStatusPulsing = true
            // On non-notched devices, keep visible so users have a target to interact with
            if !viewModel.hasPhysicalNotch {
                isVisible = true
            }
            refreshBehaviorVisibility()
        }
        .onReceive(visibilityTimer) { _ in
            refreshBehaviorVisibility()
        }
        .onChange(of: viewModel.status) { oldStatus, newStatus in
            handleStatusChange(from: oldStatus, to: newStatus)
        }
        .onChange(of: sessionMonitor.pendingInstances) { _, sessions in
            handlePendingSessionsChange(sessions)
        }
        .onChange(of: sessionMonitor.instances) { _, instances in
            handleProcessingChange()
            handleWaitingForInputChange(instances)
        }
    }

    // MARK: - Notch Layout

    private var isProcessing: Bool {
        activityCoordinator.expandingActivity.show && activityCoordinator.expandingActivity.type == .claude
    }

    /// Whether to show the expanded closed state (processing, pending permission, or waiting for input)
    private var showClosedActivity: Bool {
        isProcessing || hasPendingPermission || hasWaitingForInput
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - always present, contains crab and spinner that persist across states
            headerRow
                .frame(height: closedNotchHeight)

            // Main content only when opened
            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24) // Fixed width to prevent reflow
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Header Row (persists across states)

    @ViewBuilder
    private var headerRow: some View {
        if viewModel.status == .opened {
            HStack(spacing: 0) {
                if showClosedActivity {
                    HStack(spacing: 4) {
                        NotchDragonIcon(size: 14, color: headerStatusColor, pose: closedDinoPose, animate: headerStatusShouldAnimate)
                            .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: showClosedActivity)
                    }
                    .frame(width: 22)
                    .padding(.leading, 7)
                }

                openedHeaderContent

                if showClosedActivity {
                    NotchFireStatusIcon(size: 14, color: headerStatusColor, animate: headerStatusShouldAnimate)
                        .matchedGeometryEffect(id: "spinner", in: activityNamespace, isSource: showClosedActivity)
                        .frame(width: 20)
                }
            }
            .frame(height: closedNotchSize.height)
        } else {
            closedHeaderContent
        }
    }

    private var closedHeaderContent: some View {
        HStack(spacing: 7) {
            HStack(spacing: 4) {
                NotchDragonIcon(size: 12, color: closedStatusColor, pose: closedDinoPose, animate: headerStatusShouldAnimate)
                    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: showClosedActivity)
            }
            .fixedSize()

            if let summary = closedSummaryText {
                Text(summary)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: closedSummaryTextWidth, alignment: .leading)
                    .layoutPriority(1)

                if closedSummaryCount > 1 {
                    Text("\(closedSummaryCount)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize()
                }
            }

            closedStatusIndicator
        }
        .padding(.horizontal, closedSummaryText == nil ? 9 : 11)
        .frame(height: closedNotchHeight)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: closedMaximumWidth)
    }

    private var closedSummaryText: String? {
        guard let session = summarizedSession else { return nil }

        if hasPendingPermission, let tool = session.pendingToolName {
            let toolLabel = MCPToolFormatter.formatToolName(tool)
            return "\(NSLocalizedString("Approve", comment: "")): \(compactClosedText(toolLabel, limit: 16))"
        }

        if session.phase == .compacting {
            return "\(NSLocalizedString("Compact", comment: "")): \(compactClosedText(session.displayTitle, limit: 18))"
        }

        if session.phase == .processing || isAnyProcessing {
            if let tool = session.lastToolName {
                let toolLabel = MCPToolFormatter.formatToolName(tool)
                let detail = compactClosedText(session.lastMessage ?? session.displayTitle, limit: 18)
                return "\(toolLabel): \(detail)"
            }

            return "\(NSLocalizedString("Run", comment: "")): \(compactClosedText(session.displayTitle, limit: 18))"
        }

        if session.phase == .waitingForInput || hasWaitingForInput {
            return "\(NSLocalizedString("Read", comment: "")): \(compactClosedText(session.displayTitle, limit: 18))"
        }

        if updateManager.hasUnseenUpdate {
            return NSLocalizedString("Update available", comment: "")
        }

        return compactClosedText(session.displayTitle, limit: 16)
    }

    private var summarizedSession: SessionState? {
        let candidates: [SessionState]
        if hasPendingPermission {
            candidates = sessionMonitor.instances.filter { $0.phase.isWaitingForApproval }
        } else if isAnyProcessing {
            candidates = sessionMonitor.instances.filter { $0.phase == .processing || $0.phase == .compacting }
        } else if hasWaitingForInput {
            candidates = sessionMonitor.instances.filter { $0.phase == .waitingForInput }
        } else {
            candidates = sessionMonitor.instances
        }

        return candidates.sorted { lhs, rhs in
            let lhsDate = lhs.lastUserMessageDate ?? lhs.lastActivity
            let rhsDate = rhs.lastUserMessageDate ?? rhs.lastActivity
            return lhsDate > rhsDate
        }.first
    }

    private var closedSummaryCount: Int {
        if hasPendingPermission {
            return sessionMonitor.instances.filter { $0.phase.isWaitingForApproval }.count
        }
        if isAnyProcessing {
            return sessionMonitor.instances.filter { $0.phase == .processing || $0.phase == .compacting }.count
        }
        if hasWaitingForInput {
            return sessionMonitor.instances.filter { $0.phase == .waitingForInput }.count
        }
        return sessionMonitor.instances.count
    }

    private var closedSummaryTextWidth: CGFloat {
        let trailingWidth: CGFloat = closedSummaryCount > 1 ? 26 : 16
        let leadingWidth: CGFloat = hasPendingPermission ? 38 : 22
        return max(56, closedMaximumWidth - leadingWidth - trailingWidth - 24)
    }

    @ViewBuilder
    private var closedStatusIndicator: some View {
        NotchFireStatusIcon(size: 11, color: closedStatusColor, animate: closedStatusShouldPulse)
            .scaleEffect(closedStatusShouldPulse && isClosedStatusPulsing ? 1.0 : 0.94)
            .opacity(closedStatusShouldPulse ? (isClosedStatusPulsing ? 1.0 : 0.86) : 0.82)
            .animation(
                closedStatusShouldPulse
                    ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
                    : .easeOut(duration: 0.2),
                value: isClosedStatusPulsing
            )
            .fixedSize()
            .accessibilityLabel(Text(closedStatusAccessibilityLabel))
    }

    private var closedStatusColor: Color {
        if hasPendingPermission {
            return TerminalColors.amber
        }

        guard let session = summarizedSession else {
            return updateManager.hasUnseenUpdate ? TerminalColors.blue : TerminalColors.dim
        }

        switch session.phase {
        case .waitingForApproval:
            return TerminalColors.amber
        case .waitingForInput:
            return TerminalColors.green
        case .processing:
            return TerminalColors.cyan
        case .compacting:
            return TerminalColors.magenta
        case .idle, .ended:
            return updateManager.hasUnseenUpdate ? TerminalColors.blue : TerminalColors.dim
        }
    }

    private var closedStatusShouldPulse: Bool {
        hasPendingPermission || isAnyProcessing || hasWaitingForInput || updateManager.hasUnseenUpdate
    }

    private var closedStatusAccessibilityLabel: String {
        if hasPendingPermission {
            return NSLocalizedString("Waiting for approval", comment: "")
        }
        if let session = summarizedSession {
            return SessionPhaseHelpers.phaseDescription(for: session.phase)
        }
        return updateManager.hasUnseenUpdate
            ? NSLocalizedString("Update available", comment: "")
            : NSLocalizedString("Idle", comment: "")
    }

    private var headerStatusColor: Color {
        if hasPendingPermission {
            return TerminalColors.amber
        }
        if let session = summarizedSession {
            switch session.phase {
            case .waitingForApproval:
                return TerminalColors.amber
            case .waitingForInput:
                return TerminalColors.green
            case .processing:
                return TerminalColors.cyan
            case .compacting:
                return TerminalColors.magenta
            case .idle, .ended:
                return updateManager.hasUnseenUpdate ? TerminalColors.blue : TerminalColors.dim
            }
        }
        return updateManager.hasUnseenUpdate ? TerminalColors.blue : TerminalColors.dim
    }

    private var headerStatusShouldAnimate: Bool {
        hasPendingPermission || isAnyProcessing || hasWaitingForInput || updateManager.hasUnseenUpdate
    }

    private var closedDinoPose: NotchDinoPose {
        if hasPendingPermission {
            return .ducking
        }
        guard let session = summarizedSession else {
            return .waiting
        }
        switch session.phase {
        case .waitingForApproval:
            return .ducking
        case .waitingForInput:
            return .jumping
        case .processing:
            return .running
        case .compacting:
            return .running
        case .idle:
            return .waiting
        case .ended:
            return .crashed
        }
    }

    private func compactClosedText(_ text: String, limit: Int = 26) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if singleLine.count <= limit {
            return singleLine
        }

        return String(singleLine.prefix(limit)) + "…"
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 12) {
            // Show static crab only if not showing activity in headerRow
            // (headerRow handles crab + indicator when showClosedActivity is true)
            if !showClosedActivity {
                NotchDragonIcon(size: 14, color: Color.white.opacity(0.78), pose: .waiting, animate: false)
                    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: !showClosedActivity)
                    .padding(.leading, 8)
            }

            Spacer()

            // Menu toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.toggleMenu()
                    if viewModel.contentType == .menu {
                        updateManager.markUpdateSeen()
                    }
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: viewModel.contentType == .menu ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())

                    // Green dot for unseen update
                    if updateManager.hasUnseenUpdate && viewModel.contentType != .menu {
                        Circle()
                            .fill(TerminalColors.green)
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: 2)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content View (Opened State)

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .instances:
                ClaudeInstancesView(
                    sessionMonitor: sessionMonitor
                )
            case .menu:
                NotchMenuView(viewModel: viewModel)
            case .chat(let session):
                ChatView(
                    sessionId: session.sessionId,
                    initialSession: session,
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            }
        }
        .frame(width: notchSize.width - 24) // Fixed width to prevent text reflow
        // Removed .id() - was causing view recreation and performance issues
    }

    // MARK: - Event Handlers

    private func handleProcessingChange() {
        if isAnyProcessing || hasPendingPermission {
            // Show claude activity when processing or waiting for permission
            activityCoordinator.showActivity(type: .claude)
            isVisible = true
        } else if hasWaitingForInput {
            // Keep visible for waiting-for-input but hide the processing spinner
            activityCoordinator.hideActivity()
            isVisible = true
        } else {
            // Hide activity when done
            activityCoordinator.hideActivity()

            // Delay hiding the notch until animation completes
            // Don't hide on non-notched devices - users need a visible target
            if viewModel.status == .closed && viewModel.hasPhysicalNotch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !isAnyProcessing && !hasPendingPermission && !hasWaitingForInput && viewModel.status == .closed {
                        isVisible = false
                    }
                }
            }
        }
    }

    private func handleStatusChange(from oldStatus: NotchStatus, to newStatus: NotchStatus) {
        switch newStatus {
        case .opened, .popping:
            isVisible = true
            // Clear waiting-for-input timestamps only when manually opened (user acknowledged)
            if viewModel.openReason == .click || viewModel.openReason == .hover {
                waitingForInputTimestamps.removeAll()
            }
        case .closed:
            if !AppSettings.autoHideNoActiveSessions {
                return
            }
            // Don't hide on non-notched devices unless behavior toggle allows it
            guard viewModel.hasPhysicalNotch || sessionMonitor.instances.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if viewModel.status == .closed && !isAnyProcessing && !hasPendingPermission && !hasWaitingForInput && !activityCoordinator.expandingActivity.show {
                    isVisible = false
                }
            }
        }
    }

    private func handlePendingSessionsChange(_ sessions: [SessionState]) {
        let currentIds = Set(sessions.map { $0.stableId })
        let newPendingIds = currentIds.subtracting(previousPendingIds)

        let newPendingSessions = sessions.filter { newPendingIds.contains($0.stableId) }
        if !newPendingSessions.isEmpty && viewModel.status == .closed {
            Task {
                let shouldSuppress = await shouldSuppressAutoOpen(for: newPendingSessions)
                await MainActor.run {
                    if !shouldSuppress && !TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace() {
                        viewModel.notchOpen(reason: .notification)
                    }
                }
            }
        }

        previousPendingIds = currentIds
    }

    private func handleWaitingForInputChange(_ instances: [SessionState]) {
        // Get sessions that are now waiting for input
        let waitingForInputSessions = instances.filter { $0.phase == .waitingForInput }
        let currentIds = Set(waitingForInputSessions.map { $0.stableId })
        let newWaitingIds = currentIds.subtracting(previousWaitingForInputIds)

        // Track timestamps for newly waiting sessions
        let now = Date()
        for session in waitingForInputSessions where newWaitingIds.contains(session.stableId) {
            waitingForInputTimestamps[session.stableId] = now
        }

        // Clean up timestamps for sessions no longer waiting
        let staleIds = Set(waitingForInputTimestamps.keys).subtracting(currentIds)
        for staleId in staleIds {
            waitingForInputTimestamps.removeValue(forKey: staleId)
        }

        // Bounce the notch when a session newly enters waitingForInput state
        if !newWaitingIds.isEmpty {
            // Get the sessions that just entered waitingForInput
            let newlyWaitingSessions = waitingForInputSessions.filter { newWaitingIds.contains($0.stableId) }

            // Play notification sound if the session is not actively focused
            if let soundName = AppSettings.notificationSound.soundName {
                // Check if we should play sound (async check for tmux pane focus)
                Task {
                    let shouldPlaySound = await shouldPlayNotificationSound(for: newlyWaitingSessions)
                    if shouldPlaySound {
                        _ = await MainActor.run {
                            NSSound(named: soundName)?.play()
                        }
                    }
                }
            }

            // Trigger bounce animation to get user's attention
            DispatchQueue.main.async {
                isBouncing = true
                // Bounce back after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isBouncing = false
                }
            }

            // Schedule hiding the checkmark after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in
                // Trigger a UI update to re-evaluate hasWaitingForInput
                handleProcessingChange()
            }
        }

        previousWaitingForInputIds = currentIds
    }

    /// Determine if notification sound should play for the given sessions
    /// Returns true if ANY session is not actively focused
    private func shouldPlayNotificationSound(for sessions: [SessionState]) async -> Bool {
        for session in sessions {
            guard let pid = session.pid else {
                // No PID means we can't check focus, assume not focused
                return true
            }

            let isFocused = await TerminalVisibilityDetector.isSessionFocused(sessionPid: pid)
            if !isFocused {
                return true
            }
        }

        return false
    }

    private func refreshBehaviorVisibility() {
        let shouldHideForFullscreen =
            AppSettings.hideInFullscreen &&
            DisplayModeDetector.isFrontmostAppFullscreen(on: NSScreen.main)

        let shouldHideForIdle =
            AppSettings.autoHideNoActiveSessions &&
            viewModel.status == .closed &&
            sessionMonitor.instances.isEmpty &&
            !isAnyProcessing &&
            !hasPendingPermission &&
            !hasWaitingForInput

        isBehaviorHidden = shouldHideForFullscreen || shouldHideForIdle
    }

    private func shouldSuppressAutoOpen(for sessions: [SessionState]) async -> Bool {
        guard AppSettings.smartSuppression else { return false }

        for session in sessions {
            guard let pid = session.pid else { continue }
            if await TerminalVisibilityDetector.isSessionFocused(sessionPid: pid) {
                return true
            }
        }

        return false
    }
}
