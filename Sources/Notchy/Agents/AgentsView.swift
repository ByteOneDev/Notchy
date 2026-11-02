import SwiftUI

/// Small colored mark for an agent ("Claude", "Codex"…).
struct AgentGlyph: View {
    let name: String
    var size: CGFloat = 13

    private var kind: AgentKind {
        AgentKind.allCases.first { $0.displayName == name } ?? .other
    }

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(kind.color)
    }
}


/// What the coding agents are doing: steps, last message, permission prompts and usage.
struct AgentsView: View {
    @ObservedObject private var hub = AgentHub.shared

    var body: some View {
        if let session = hub.selectedSession {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    header(session)
                    steps(session)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    if let prompt = hub.pendingPermissions.first(where: { $0.sessionID == session.id }) ?? hub.pendingPermissions.first {
                        PermissionCard(prompt: prompt)
                    } else if let message = session.lastMessage {
                        MessageBubble(text: message)
                    }
                    Spacer(minLength: 0)
                    UsageMeters(usage: hub.usage)
                }
                .frame(width: 300)
            }
        } else {
            emptyState
        }
    }

    private func header(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.indent").font(.system(size: 10))
                Text(L("agents.progress")).font(.system(size: 11, weight: .medium))
                Spacer()
                if hub.sessions.count > 1 {
                    // Switch between running sessions.
                    HStack(spacing: 4) {
                        ForEach(hub.sessions.prefix(5)) { other in
                            Button { hub.selectedSessionID = other.id } label: {
                                Circle()
                                    .fill(other.kind.color.opacity(other.id == session.id ? 1 : 0.35))
                                    .frame(width: 7, height: 7)
                            }
                            .buttonStyle(.plain)
                            .help("\(other.kind.displayName) · \(other.project)")
                        }
                    }
                }
            }
            .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 6) {
                AgentGlyph(name: session.kind.displayName, size: 13)
                Text(session.kind.displayName).font(.system(size: 14, weight: .bold))
                Circle().fill(session.kind.color).frame(width: 4, height: 4)
                Text(session.prompt ?? session.project)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(session.kind.color)
                    .lineLimit(1)
            }
        }
    }

    private func steps(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            let recent = Array(session.steps.suffix(session.isWorking ? 3 : 4))
            ForEach(recent) { step in
                HStack(spacing: 7) {
                    Image(systemName: step.done ? "checkmark" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(step.done ? .white.opacity(0.6) : session.kind.color)
                        .frame(width: 12)
                    Text(step.title).font(.system(size: 12)).lineLimit(1)
                        .foregroundStyle(.white.opacity(step.done ? 0.75 : 1))
                }
                .transition(.push(from: .bottom).combined(with: .opacity))
            }
            if session.isWorking, session.steps.last?.done != false {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(session.kind.color).frame(width: 12)
                    Text(L("agents.thinking")).font(.system(size: 12))
                        .phaseAnimator([0.4, 1]) { text, phase in text.opacity(phase) } animation: { _ in .easeInOut(duration: 0.8) }
                }
            } else if !session.isWorking {
                Label(L("agents.idle"), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11)).foregroundStyle(.green.opacity(0.8))
            }
        }
        .animation(.snappy, value: session.steps)
    }

    private var emptyState: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06))
                Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(AgentKind.claude.color)
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("agents.empty")).font(.system(size: 15, weight: .semibold))
                Text(L("agents.emptyHint")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                if AgentIntegrations.claudeState == .notInstalled {
                    Button(L("agents.connect")) { SettingsWindowController.shared.show(pane: .agents) }
                        .buttonStyle(PillButtonStyle())
                }
            }
            Spacer(minLength: 0)
            UsageMeters(usage: hub.usage).frame(width: 220)
        }
    }
}

private struct MessageBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(5)
            .multilineTextAlignment(.leading)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08)))
    }
}

private struct PermissionCard: View {
    let prompt: PermissionPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                Text(L("agents.permission", prompt.kind.displayName, prompt.tool))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, AgentHub.permissionTimeout - context.date.timeIntervalSince(prompt.createdAt))
                    Text("\(Int(left))s").font(.system(size: 9).monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                }
            }
            Text(prompt.detail)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(3)
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
            HStack(spacing: 6) {
                Button(L("agents.allow")) { prompt.respond(true) }
                    .buttonStyle(PillButtonStyle(color: .green))
                    .keyboardShortcut(.return, modifiers: [])
                Button(L("agents.deny")) { prompt.respond(false) }
                    .buttonStyle(PillButtonStyle(color: .red.opacity(0.85)))
                Spacer(minLength: 0)
                Button(L("agents.inTerminal")) { prompt.respond(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.orange.opacity(0.3)))
    }
}

/// Session (5 h) and weekly limits, as reported by Claude Code's status line.
struct UsageMeters: View {
    let usage: AgentUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            meter(L("usage.session"), usage.fiveHour, usage.fiveHourReset)
            meter(L("usage.week"), usage.sevenDay, usage.sevenDayReset)
        }
    }

    private func meter(_ title: String, _ percent: Double?, _ reset: Date?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                if let percent {
                    Text("\(Int(percent.rounded())) %").font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(color(percent))
                } else {
                    Text("—").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color(percent ?? 0)).frame(width: geo.size.width * min(1, (percent ?? 0) / 100))
                }
            }
            .frame(height: 4)
            if let reset, percent != nil {
                Text(L("usage.resets", reset.formatted(.relative(presentation: .named).locale(Loc.locale))))
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private func color(_ percent: Double) -> Color {
        percent >= 95 ? .red : percent >= Double(AppSettings.shared.usageAlertThreshold) ? .orange : AgentKind.claude.color
    }
}
