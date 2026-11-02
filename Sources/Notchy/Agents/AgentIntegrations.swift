import Foundation

/// Connects coding agents to Notchy. Each install is triggered from the settings, backs up the
/// file it changes, and only touches entries pointing at Notchy's local server.
@MainActor
enum AgentIntegrations {
    static let baseURL = "http://127.0.0.1:\(LocalServer.port)"
    static let hookURL = "\(baseURL)/claude/hook"
    static let statusCommand = "curl -s -m 1 --data-binary @- \(baseURL)/claude/status || true"

    private static let claudeSettings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    private static let codexConfig = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")

    private static let claudeEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    // MARK: Claude Code

    enum ClaudeState: Equatable {
        case notInstalled, installed, installedWithoutStatusLine
    }

    static var claudeState: ClaudeState {
        guard let settings = readClaudeSettings(), let hooks = settings["hooks"] as? [String: Any],
              hooks["PermissionRequest"].map(containsNotchy) == true else { return .notInstalled }
        let statusCommand = (settings["statusLine"] as? [String: Any])?["command"] as? String
        return statusCommand?.contains(baseURL) == true ? .installed : .installedWithoutStatusLine
    }

    /// Statusline command already set by the user (Notchy never replaces it).
    static var foreignStatusLine: String? {
        guard let command = (readClaudeSettings()?["statusLine"] as? [String: Any])?["command"] as? String,
              !command.contains(baseURL) else { return nil }
        return command
    }

    static func installClaude() throws {
        var settings = readClaudeSettings() ?? [:]
        try backup(claudeSettings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in claudeEvents + ["PermissionRequest"] {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !containsNotchy($0) }
            let timeout = event == "PermissionRequest" ? Int(AgentHub.permissionTimeout) + 15 : 5
            groups.append(["hooks": [["type": "http", "url": hookURL, "timeout": timeout]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        // The status line feeds the usage meters; keep the user's own if they have one.
        if foreignStatusLine == nil {
            settings["statusLine"] = ["type": "command", "command": statusCommand]
        }
        try writeClaudeSettings(settings)
    }

    static func uninstallClaude() throws {
        guard var settings = readClaudeSettings() else { return }
        try backup(claudeSettings)
        if var hooks = settings["hooks"] as? [String: Any] {
            for (event, value) in hooks {
                let groups = (value as? [[String: Any]] ?? []).filter { !containsNotchy($0) }
                hooks[event] = groups.isEmpty ? nil : groups
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
        }
        if ((settings["statusLine"] as? [String: Any])?["command"] as? String)?.contains(baseURL) == true {
            settings["statusLine"] = nil
        }
        try writeClaudeSettings(settings)
    }

    private static func containsNotchy(_ value: Any) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("127.0.0.1:\(LocalServer.port)")
    }

    private static func readClaudeSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: claudeSettings) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func writeClaudeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: claudeSettings, options: .atomic)
    }

    // MARK: Codex

    enum CodexState: Equatable {
        case notInstalled, installed, otherNotify, codexMissing
    }

    private static var codexNotifyLine: String {
        #"notify = ["curl", "-s", "-m", "2", "-H", "Content-Type: application/json", "\#(baseURL)/codex", "-d"]"#
    }

    static var codexState: CodexState {
        guard FileManager.default.fileExists(atPath: codexConfig.deletingLastPathComponent().path) else { return .codexMissing }
        let text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        guard let line = text.components(separatedBy: .newlines).first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }) else {
            return .notInstalled
        }
        return line.contains(baseURL) ? .installed : .otherNotify
    }

    /// Codex runs `notify` with the event JSON appended as the last argument, so curl posts it.
    static func installCodex() throws {
        guard codexState == .notInstalled else { return }
        let text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        try backup(codexConfig)
        // `notify` is a top-level key: it must come before the first [table].
        let updated = "# Notchy: shows Codex turns in the notch\n\(codexNotifyLine)\n\n" + text
        try updated.write(to: codexConfig, atomically: true, encoding: .utf8)
    }

    static func uninstallCodex() throws {
        guard codexState == .installed else { return }
        let text = try String(contentsOf: codexConfig, encoding: .utf8)
        try backup(codexConfig)
        let kept = text.components(separatedBy: "\n").filter { line in
            !(line.contains(baseURL) && line.hasPrefix("notify")) && line != "# Notchy: shows Codex turns in the notch"
        }
        try kept.joined(separator: "\n").trimmingCharacters(in: .newlines).appending("\n").write(to: codexConfig, atomically: true, encoding: .utf8)
    }

    // MARK: -

    private static func backup(_ file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let copy = file.appendingPathExtension("notchy-backup")
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: file, to: copy)
    }
}
