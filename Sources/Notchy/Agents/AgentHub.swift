import AppKit
import SwiftUI

enum AgentKind: String, CaseIterable {
    case claude, codex, gemini, other

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .other: L("agents.agent")
        }
    }

    var color: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.6, green: 0.8, blue: 1)
        case .gemini: Color(red: 0.5, green: 0.55, blue: 1)
        case .other: .white
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkles"
        case .other: "cpu"
        }
    }
}

struct AgentStep: Identifiable, Equatable {
    let id = UUID()
    let toolUseID: String?
    var title: String
    var done: Bool
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    let kind: AgentKind
    var project: String
    var prompt: String?
    var steps: [AgentStep] = []
    var isWorking = false
    var lastMessage: String?
    var updatedAt = Date.now
}

struct PermissionPrompt: Identifiable {
    let id = UUID()
    let sessionID: String
    let kind: AgentKind
    let project: String
    let tool: String
    let detail: String
    let createdAt = Date.now
    let respond: @MainActor (Bool?) -> Void
}

struct AgentUsage: Equatable, Codable {
    var fiveHour: Double?
    var fiveHourReset: Date?
    var sevenDay: Double?
    var sevenDayReset: Date?
    /// When Claude Code last reported it.
    var updatedAt: Date?

    var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    /// A window whose reset time has passed starts again from zero.
    func current(_ percent: Double?, reset: Date?) -> Double? {
        guard let percent else { return nil }
        if let reset, reset < .now { return 0 }
        return percent
    }
}

/// Everything the coding agents report: sessions, steps, permission prompts and usage.
@MainActor
final class AgentHub: ObservableObject {
    static let shared = AgentHub()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var pendingPermissions: [PermissionPrompt] = []
    @Published private(set) var usage = AgentUsage()
    @Published var selectedSessionID: String?

    private let server = LocalServer()
    private var warnedUsage = Set<String>()
    /// Without an answer from the notch, the request goes back to the terminal prompt.
    static let permissionTimeout: TimeInterval = 75

    var selectedSession: AgentSession? {
        sessions.first { $0.id == selectedSessionID } ?? sessions.first
    }

    var isAnyWorking: Bool { sessions.contains { $0.isWorking } }

    func start() {
        if let data = UserDefaults.standard.data(forKey: "agentUsage"),
           let saved = try? JSONDecoder().decode(AgentUsage.self, from: data) {
            usage = saved
        }
        server.handler = { [weak self] request, respond in
            self?.handle(request, respond: respond) ?? respond(.init(status: 503))
        }
        server.start()
        // Forget sessions idle for a long time.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let hub = AgentHub.shared
                hub.sessions.removeAll { !$0.isWorking && Date.now.timeIntervalSince($0.updatedAt) > 3 * 3600 }
            }
        }
    }

    private func handle(_ request: LocalServer.Request, respond: @escaping @MainActor (LocalServer.Response) -> Void) {
        let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        switch request.path {
        case "/claude/hook":
            handleClaudeHook(json, respond: respond)
        case "/claude/status":
            updateUsage(from: json)
            respond(.text(Self.statusLine(from: json, usage: usage)))
        case "/codex":
            handleCodex(json)
            respond(.json([:]))
        case "/agent":
            handleGeneric(json)
            respond(.json([:]))
        case let path where path.hasPrefix("/blocked"):
            respond(SiteBlocker.shared.response(for: path))
        default:
            respond(.init(status: 404))
        }
    }

    // MARK: Claude Code

    private func handleClaudeHook(_ json: [String: Any], respond: @escaping @MainActor (LocalServer.Response) -> Void) {
        guard AppSettings.shared.agentsEnabled else { return respond(.json([:])) }
        let event = json["hook_event_name"] as? String ?? ""
        let sessionID = json["session_id"] as? String ?? "claude"
        let project = (json["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code"
        var session = sessions.first { $0.id == sessionID } ?? AgentSession(id: sessionID, kind: .claude, project: project)
        session.project = project
        session.updatedAt = .now

        switch event {
        case "SessionStart":
            session.isWorking = false
        case "UserPromptSubmit":
            session.prompt = (json["prompt"] as? String)?.components(separatedBy: .newlines).first
            session.steps = []
            session.lastMessage = nil
            session.isWorking = true
        case "PreToolUse":
            session.isWorking = true
            let title = Self.stepTitle(tool: json["tool_name"] as? String ?? "", input: json["tool_input"] as? [String: Any] ?? [:])
            session.steps.append(AgentStep(toolUseID: json["tool_use_id"] as? String, title: title, done: false))
            if session.steps.count > 30 { session.steps.removeFirst(session.steps.count - 30) }
        case "PostToolUse", "PostToolUseFailure":
            let toolUseID = json["tool_use_id"] as? String
            if let index = session.steps.lastIndex(where: { !$0.done && ($0.toolUseID == nil || $0.toolUseID == toolUseID) }) {
                session.steps[index].done = true
            }
        case "Notification":
            if let message = json["message"] as? String {
                session.lastMessage = message
                if AppSettings.shared.agentActivity {
                    LiveActivityCenter.shared.show(.agentAttention(agent: AgentKind.claude.displayName, message: message), duration: 4)
                }
            }
        case "Stop", "SubagentStop":
            if event == "Stop" {
                session.isWorking = false
                for index in session.steps.indices { session.steps[index].done = true }
                if let message = json["last_assistant_message"] as? String, !message.isEmpty {
                    session.lastMessage = message
                }
                if AppSettings.shared.agentActivity {
                    LiveActivityCenter.shared.show(.agentDone(agent: AgentKind.claude.displayName, project: project), duration: 3.5)
                }
            }
        case "SessionEnd":
            sessions.removeAll { $0.id == sessionID }
            pendingPermissions.filter { $0.sessionID == sessionID }.forEach { $0.respond(nil) }
            return respond(.json([:]))
        case "PermissionRequest":
            store(session)
            askPermission(json, session: session, respond: respond)
            return
        default:
            break
        }
        store(session)
        respond(.json([:]))
    }

    private func askPermission(_ json: [String: Any], session: AgentSession, respond: @escaping @MainActor (LocalServer.Response) -> Void) {
        let tool = json["tool_name"] as? String ?? "?"
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let detail = (input["command"] as? String) ?? (input["file_path"] as? String) ?? (input["url"] as? String)
            ?? (input["description"] as? String) ?? Self.compactJSON(input)
        var prompt: PermissionPrompt!
        prompt = PermissionPrompt(sessionID: session.id, kind: session.kind, project: session.project, tool: tool, detail: detail) { [weak self] allow in
            guard let self else { return }
            self.pendingPermissions.removeAll { $0.id == prompt.id }
            switch allow {
            case true?:
                respond(.json(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow"]]]))
            case false?:
                respond(.json(["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                                      "decision": ["behavior": "deny", "message": L("agents.deniedMessage")]]]))
            case nil:
                // No decision: Claude Code shows its usual prompt in the terminal.
                respond(.json([:]))
            }
        }
        pendingPermissions.append(prompt)
        selectedSessionID = session.id
        Sounds.play(.alert)
        NotchManager.shared.openPrimary(tab: .agents)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.permissionTimeout) { [weak self] in
            guard let self, self.pendingPermissions.contains(where: { $0.id == prompt.id }) else { return }
            prompt.respond(nil)
        }
    }

    private func store(_ session: AgentSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Usage

    private func updateUsage(from json: [String: Any]) {
        guard let limits = json["rate_limits"] as? [String: Any] else { return }
        func read(_ key: String) -> (Double?, Date?) {
            guard let entry = limits[key] as? [String: Any] else { return (nil, nil) }
            let percent = (entry["used_percentage"] as? NSNumber)?.doubleValue
            let reset = (entry["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                ?? (entry["resets_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            return (percent, reset)
        }
        let (fiveHour, fiveReset) = read("five_hour")
        let (sevenDay, sevenReset) = read("seven_day")
        usage = AgentUsage(fiveHour: fiveHour, fiveHourReset: fiveReset, sevenDay: sevenDay, sevenDayReset: sevenReset, updatedAt: .now)
        // Kept across restarts (updates relaunch Notchy): Claude Code only reports it while it runs.
        if let data = try? JSONEncoder().encode(usage) { UserDefaults.standard.set(data, forKey: "agentUsage") }
        warnIfNeeded(fiveHour, reset: fiveReset, window: L("usage.session"))
        warnIfNeeded(sevenDay, reset: sevenReset, window: L("usage.week"))
    }

    /// Once per window and reset time, when usage crosses the threshold.
    private func warnIfNeeded(_ percent: Double?, reset: Date?, window: String) {
        let threshold = Double(AppSettings.shared.usageAlertThreshold)
        guard AppSettings.shared.usageAlert, let percent, percent >= threshold else { return }
        let key = "\(window)|\(reset?.timeIntervalSince1970 ?? 0)"
        guard !warnedUsage.contains(key) else { return }
        warnedUsage.insert(key)
        LiveActivityCenter.shared.show(.usageWarning(percent: Int(percent.rounded()), window: window), duration: 6)
    }

    /// The line Claude Code shows under its prompt.
    private static func statusLine(from json: [String: Any], usage: AgentUsage) -> String {
        var parts: [String] = []
        if let model = (json["model"] as? [String: Any])?["display_name"] as? String { parts.append(model) }
        if let dir = (json["workspace"] as? [String: Any])?["current_dir"] as? String {
            parts.append(URL(fileURLWithPath: dir).lastPathComponent)
        }
        if let five = usage.fiveHour { parts.append("5h \(Int(five.rounded()))%") }
        if let seven = usage.sevenDay { parts.append(L("usage.weekShort") + " \(Int(seven.rounded()))%") }
        return parts.joined(separator: " · ")
    }

    // MARK: Other agents

    /// Codex `notify` payload: sent when a turn completes.
    private func handleCodex(_ json: [String: Any]) {
        guard AppSettings.shared.agentsEnabled, json["type"] as? String == "agent-turn-complete" else { return }
        let id = json["thread-id"] as? String ?? "codex"
        let project = (json["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Codex"
        var session = sessions.first { $0.id == id } ?? AgentSession(id: id, kind: .codex, project: project)
        session.prompt = (json["input-messages"] as? [String])?.last
        session.lastMessage = json["last-assistant-message"] as? String
        session.isWorking = false
        session.updatedAt = .now
        store(session)
        if AppSettings.shared.agentActivity {
            LiveActivityCenter.shared.show(.agentDone(agent: AgentKind.codex.displayName, project: project), duration: 3.5)
        }
    }

    /// Generic endpoint for any tool: {"agent": "gemini", "session": "…", "project": "…", "status": "working|done", "step": "…", "message": "…"}.
    private func handleGeneric(_ json: [String: Any]) {
        guard AppSettings.shared.agentsEnabled else { return }
        let kind = AgentKind(rawValue: (json["agent"] as? String ?? "").lowercased()) ?? .other
        let id = json["session"] as? String ?? kind.rawValue
        var session = sessions.first { $0.id == id } ?? AgentSession(id: id, kind: kind, project: json["project"] as? String ?? kind.displayName)
        if let step = json["step"] as? String {
            for index in session.steps.indices { session.steps[index].done = true }
            session.steps.append(AgentStep(toolUseID: nil, title: step, done: false))
        }
        if let message = json["message"] as? String { session.lastMessage = message }
        let status = json["status"] as? String
        session.isWorking = status != "done"
        if status == "done" {
            for index in session.steps.indices { session.steps[index].done = true }
            LiveActivityCenter.shared.show(.agentDone(agent: kind.displayName, project: session.project), duration: 3.5)
        }
        session.updatedAt = .now
        store(session)
    }

    // MARK: Helpers

    static func stepTitle(tool: String, input: [String: Any]) -> String {
        func file(_ key: String = "file_path") -> String {
            (input[key] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        }
        switch tool {
        case "Bash": return L("agents.step.run", oneLine(input["command"] as? String ?? ""))
        case "Read": return L("agents.step.read", file())
        case "Edit", "MultiEdit": return L("agents.step.edit", file())
        case "Write": return L("agents.step.write", file())
        case "Grep", "Glob": return L("agents.step.search", oneLine(input["pattern"] as? String ?? ""))
        case "WebFetch": return L("agents.step.fetch", URL(string: input["url"] as? String ?? "")?.host() ?? "")
        case "WebSearch": return L("agents.step.search", oneLine(input["query"] as? String ?? ""))
        case "Task", "Agent": return L("agents.step.agent", oneLine(input["description"] as? String ?? ""))
        default: return tool.hasPrefix("mcp__") ? tool.split(separator: "_").last.map(String.init) ?? tool : tool
        }
    }

    private static func oneLine(_ text: String) -> String {
        let line = text.components(separatedBy: .newlines).first ?? ""
        return line.count > 70 ? String(line.prefix(70)) + "…" : line
    }

    private static func compactJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text.count > 300 ? String(text.prefix(300)) + "…" : text
    }
}
