import AppKit
import Foundation
import OSLog
import StoplightCore

private let log = Logger(subsystem: "com.timwheeler.stoplight", category: "Agent")

/// One button: worktree for the PR's branch, terminal in it, your coding agent running with the failure as its prompt (US-025).
@MainActor
enum AgentLauncher {
    enum Agent: String, CaseIterable, Identifiable {
        case claude, codex, gemini, aider, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .claude: "Claude Code"
            case .codex: "Codex"
            case .gemini: "Gemini CLI"
            case .aider: "Aider"
            case .custom: "Custom command"
            }
        }
        var binary: String? {
            switch self {
            case .claude: "claude"
            case .codex: "codex"
            case .gemini: "gemini"
            case .aider: "aider"
            case .custom: nil
            }
        }
        /// Shell command that starts the agent with a prompt. `{prompt}` is already shell-quoted.
        func command(prompt: String, custom: String) -> String {
            switch self {
            case .claude: "claude \(prompt)"
            case .codex: "codex \(prompt)"
            case .gemini: "gemini -i \(prompt)"
            case .aider: "aider --message \(prompt)"
            case .custom: custom.replacingOccurrences(of: "{prompt}", with: prompt)
            }
        }
    }

    enum Terminal: String, CaseIterable, Identifiable {
        case terminal, iterm, ghostty, warp
        var id: String { rawValue }
        var title: String {
            switch self {
            case .terminal: "Terminal"
            case .iterm: "iTerm2"
            case .ghostty: "Ghostty"
            case .warp: "Warp"
            }
        }
        var bundleID: String {
            switch self {
            case .terminal: "com.apple.Terminal"
            case .iterm: "com.googlecode.iterm2"
            case .ghostty: "com.mitchellh.ghostty"
            case .warp: "dev.warp.Warp-Stable"
            }
        }
        var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
    }

    static let defaultPrompt = """
    CI failed on PR #{number} "{title}" in {repo} (branch {branch}).
    Failing checks: {failing_checks}
    Logs: {check_urls}
    Find the root cause and fix it on this branch. Run the relevant tests locally before you finish.
    """

    enum Err: LocalizedError {
        case noRepo(String), noAgent, git(String), terminal(String)
        var errorDescription: String? {
            switch self {
            case .noRepo(let r): "No local clone for \(r). Add it in Settings → Agent → Repos."
            case .noAgent: "Pick an agent in Settings → Agent."
            case .git(let m): "git: \(m)"
            case .terminal(let m): "Couldn't open the terminal: \(m)"
            }
        }
    }

    // MARK: Detection

    /// Which agent binaries a login shell can see. Cached per launch.
    private(set) static var installedAgents: Set<Agent> = []
    static func detectAgents() async {
        let names = Agent.allCases.compactMap(\.binary)
        // `; true` so a missing last binary doesn't make the whole script exit non-zero.
        let out = (try? await shell("for b in \(names.joined(separator: " ")); do command -v $b >/dev/null 2>&1 && echo FOUND:$b; done; true")) ?? ""
        // Interactive shells may prepend terminal-integration escape codes on the first line; look past them.
        let found = Set(out.split(separator: "\n").compactMap { line -> String? in
            guard let r = line.range(of: "FOUND:") else { return nil }
            return String(line[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        })
        installedAgents = Set(Agent.allCases.filter { $0 == .custom || found.contains($0.binary ?? "") })
    }

    // MARK: Repos

    /// Scan `root` (two levels deep) for git repos and map "owner/name" → path using their origin remote.
    static func scanRepos(root: String) async -> [String: String] {
        let script = """
        for d in "\(root)"/*/ "\(root)"/*/*/; do
          [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
          u=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
          echo "$u|${d%/}"
        done
        """
        let out = (try? await shell(script)) ?? ""
        var map: [String: String] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let slug = repoSlug(fromRemote: parts[0]) else { continue }
            let key = slug.lowercased(), path = parts[1]
            // Several checkouts of one repo (worktrees, experiments): prefer the folder named after the repo, then the shortest path.
            if let existing = map[key] {
                let name = slug.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
                let a = (existing as NSString).lastPathComponent.lowercased() == name
                let b = (path as NSString).lastPathComponent.lowercased() == name
                if a && !b { continue }
                if a == b && existing.count <= path.count { continue }
            }
            map[key] = path
        }
        return map
    }

    /// git@github.com:owner/name.git or https://github.com/owner/name(.git) → "owner/name"
    static func repoSlug(fromRemote url: String) -> String? {
        guard let r = url.range(of: "github.com[:/]([^/]+/[^/\\s]+?)(\\.git)?$", options: .regularExpression) else { return nil }
        var s = String(url[r])
        s = s.replacingOccurrences(of: "github.com:", with: "").replacingOccurrences(of: "github.com/", with: "")
        if s.hasSuffix(".git") { s.removeLast(4) }
        return s
    }

    // MARK: Launch

    struct Config {
        let agent: Agent
        let customCommand: String
        let terminal: Terminal
        let promptTemplate: String
        let reviewTemplate: String
        let repoPaths: [String: String]
    }

    /// What the agent is asked to do in the worktree (US-033). (Not `Task`: that shadows Swift concurrency.)
    enum Job { case fix, review }

    static let defaultReviewPrompt = """
    Adversarially review PR #{number} "{title}" in {repo} (branch {branch} into {base}).
    Description: {description}
    Assume the author is competent and something is still wrong. Hunt for bugs, unhandled edge cases, race conditions, security issues, missing or weak tests, and misleading names or comments. Run the test suite and any linters.
    Report findings as a numbered list ordered by severity, each with file:line and a one-sentence failure scenario. Do not change code unless I ask.
    """

    /// The branch the agent works on. PRs: the PR's own branch. Branch rows (main is red): a fresh
    /// fix branch off that branch, since nobody should push straight to main.
    static func workBranch(for pr: PullRequest) -> String {
        pr.isBranch ? "fix/\(pr.headRefName.replacingOccurrences(of: "/", with: "-"))-ci-\(pr.headSha.prefix(7))" : pr.headRefName
    }

    /// Create or reuse the worktree. Returns its path.
    static func worktree(for pr: PullRequest, config: Config) async throws -> String {
        guard let clone = config.repoPaths[pr.repo.lowercased()] else { throw Err.noRepo(pr.repo) }
        let branch = workBranch(for: pr)
        let base = pr.headRefName   // for a PR this is the same branch; for a branch row it's the branch to fork from
        let safe = branch.replacingOccurrences(of: "/", with: "-")
        let repoName = (clone as NSString).lastPathComponent
        let path = ((clone as NSString).deletingLastPathComponent as NSString).appendingPathComponent("\(repoName)-\(safe)")
        if FileManager.default.fileExists(atPath: path) { return path }
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        set -e
        cd \(q(clone))
        git fetch origin \(q(base))
        if git show-ref --verify --quiet refs/heads/\(q(branch)); then
          git worktree add \(q(path)) \(q(branch))
        elif git show-ref --verify --quiet refs/remotes/origin/\(q(branch)); then
          git worktree add --track -b \(q(branch)) \(q(path)) origin/\(q(branch))
        else
          git worktree add -b \(q(branch)) \(q(path)) origin/\(q(base))
        fi
        """
        do { _ = try await shell(script) } catch let e as ShellError { throw Err.git(e.output) }
        return path
    }

    /// Branch rows don't have a PR to describe, so they get their own prompt.
    static let branchPrompt = """
    CI failed on {repo} branch {branch} at commit {sha} ("{title}").
    Failing checks: {failing_checks}
    Logs: {check_urls}
    You are on a fresh branch off {branch}. Find the root cause, fix it, run the relevant tests locally, then open a PR against {branch}.
    """

    static func prompt(for pr: PullRequest, template: String) -> String {
        let failing = pr.failingChecks
        let template = pr.isBranch ? branchPrompt : template
        return template
            .replacingOccurrences(of: "{sha}", with: String(pr.headSha.prefix(7)))
            .replacingOccurrences(of: "{base}", with: pr.baseRefName.isEmpty ? "the base branch" : pr.baseRefName)
            .replacingOccurrences(of: "{number}", with: String(pr.number))
            .replacingOccurrences(of: "{title}", with: pr.title)
            .replacingOccurrences(of: "{repo}", with: pr.repo)
            .replacingOccurrences(of: "{branch}", with: pr.headRefName)
            .replacingOccurrences(of: "{url}", with: pr.url.absoluteString)
            .replacingOccurrences(of: "{failing_checks}", with: failing.isEmpty ? "none reported" : failing.map(\.name).joined(separator: ", "))
            .replacingOccurrences(of: "{check_urls}", with: failing.compactMap { $0.url?.absoluteString }.joined(separator: "\n"))
            .replacingOccurrences(of: "{description}", with: pr.summary)
    }

    /// Worktree → terminal → agent. `runAgent == false` just opens the terminal in the worktree.
    static func fix(_ pr: PullRequest, config: Config, runAgent: Bool, task: Job = .fix) async throws {
        let path = try await worktree(for: pr, config: config)
        var command = "cd \(shq(path))"
        if runAgent {
            let template = task == .review ? config.reviewTemplate : config.promptTemplate
            let p = prompt(for: pr, template: template)
            command += " && " + config.agent.command(prompt: shq(p), custom: config.customCommand)
        }
        try await openTerminal(config.terminal, command: command, directory: path)
        log.notice("launched \(config.agent.rawValue, privacy: .public) (\(String(describing: task), privacy: .public)) in \(path, privacy: .public)")
    }

    /// Write a small launcher script and hand it to the terminal. Sidesteps per-terminal quoting rules and,
    /// for Terminal/iTerm, the AppleScript automation prompt.
    private static func launcherScript(command: String, directory: String) throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Stoplight/launch")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("fix-\(Int(Date.now.timeIntervalSince1970)).command")
        let body = """
        #!/bin/zsh
        export PATH="\(extraPath):$PATH"
        cd \(shq(directory))
        clear
        \(command)
        exec /bin/zsh -il
        """
        try body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private static func openTerminal(_ t: Terminal, command: String, directory: String) async throws {
        // Only the agent command goes in the script; `cd` is handled there too.
        let agentOnly = command.replacingOccurrences(of: "cd \(shq(directory)) && ", with: "").replacingOccurrences(of: "cd \(shq(directory))", with: "")
        let script = try launcherScript(command: agentOnly, directory: directory)
        switch t {
        case .terminal:
            _ = try await shell("open -a Terminal \(shq(script.path))")
        case .iterm:
            _ = try await shell("open -a iTerm \(shq(script.path))")
        case .ghostty:
            _ = try await shell("open -na Ghostty --args --working-directory=\(shq(directory)) --command=\(shq(script.path))")
        case .warp:
            // Warp has no scriptable "run this": open the folder and put the command on the clipboard.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(agentOnly, forType: .string)
            _ = try await shell("open -a Warp \(shq(directory))")
        }
    }

    // MARK: Shell helpers

    struct ShellError: Error { let output: String }

    /// Common install dirs that may only be on PATH via .zshrc; prepended so detection and launch see them.
    nonisolated static var extraPath: String {
        let home = NSHomeDirectory()
        var dirs = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.cargo/bin", "\(home)/.claude/local"]
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            dirs += versions.sorted().reversed().map { "\(home)/.nvm/versions/node/\($0)/bin" }
        }
        return dirs.joined(separator: ":")
    }

    /// Runs under an interactive login zsh (so .zprofile AND .zshrc apply) with common tool dirs prepended.
    @discardableResult
    static func shell(_ script: String) async throws -> String {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-ilc", "export PATH=\"\(extraPath):$PATH\"; " + script]
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "dumb"   // keep prompt frameworks quiet in a non-tty shell
            p.environment = env
            let out = Pipe(); p.standardOutput = out; p.standardError = out
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard p.terminationStatus == 0 else { throw ShellError(output: text) }
            return text
        }.value
    }

    /// Single-quote for POSIX shells.
    static func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
