import Foundation
import Security

/// Reads the session (5 h) and weekly limits straight from Anthropic, with the login that
/// Claude Code's command line keeps in the keychain, so they show up even when Claude Code
/// isn't running in the Terminal. Read only: the login is never refreshed or written here
/// (that would sign Claude Code out); when it expires, Claude Code renews it next time it runs.
@MainActor
final class AccountUsage: ObservableObject {
    static let shared = AccountUsage()

    enum State: Equatable {
        case idle, ok
        /// No Claude Code login in the keychain: `claude`, then `/login`, in the Terminal.
        case notLoggedIn
        /// The login has expired; Claude Code renews it when it runs.
        case expired
        /// Access to the keychain item was refused.
        case denied
        case failed
    }

    @Published private(set) var state: State = .idle
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { AccountUsage.shared.refresh() }
        }
    }

    func refresh() {
        let settings = AppSettings.shared
        // Once refused, don't ask again until the next launch or a manual retry.
        guard settings.agentsEnabled, settings.usageFromAccount, state != .denied else { return }
        Task {
            let result = await Self.fetch()
            state = result.state
            if let usage = result.usage { AgentHub.shared.setUsage(usage) }
        }
    }

    func retry() {
        state = .idle
        refresh()
    }

    private struct Login {
        let token: String
        let expiresAt: Date?
    }

    nonisolated private static func fetch() async -> (state: State, usage: AgentUsage?) {
        let login: Login
        switch await Task.detached(operation: readLogin).value {
        case let .success(found): login = found
        case let .failure(failure): return (failure.state, nil)
        }
        if let expiry = login.expiresAt, expiry < .now { return (.expired, nil) }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(login.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Notchy", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return (.failed, nil) }
        if status == 401 { return (.expired, nil) }
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (.failed, nil) }
        func window(_ key: String) -> (Double?, Date?) {
            guard let entry = json[key] as? [String: Any] else { return (nil, nil) }
            return ((entry["utilization"] as? NSNumber)?.doubleValue, (entry["resets_at"] as? String).flatMap(parseDate))
        }
        let (fiveHour, fiveReset) = window("five_hour")
        let (sevenDay, sevenReset) = window("seven_day")
        guard fiveHour != nil || sevenDay != nil else { return (.failed, nil) }
        return (.ok, AgentUsage(fiveHour: fiveHour, fiveHourReset: fiveReset, sevenDay: sevenDay, sevenDayReset: sevenReset, updatedAt: .now))
    }

    private struct Failure: Error { let state: State }

    /// The access token from Claude Code's keychain item. macOS asks the user the first time.
    nonisolated private static func readLogin() -> Result<Login, Failure> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: return .failure(Failure(state: .notLoggedIn))
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed: return .failure(Failure(state: .denied))
        default: return .failure(Failure(state: .failed))
        }
        guard let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return .failure(Failure(state: .notLoggedIn)) }
        let expiry = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return .success(Login(token: token, expiresAt: expiry))
    }

    /// ISO 8601, with or without fractional seconds of any length.
    nonisolated private static func parseDate(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
