import SwiftUI
import StoplightCore

/// Settings → Agent (US-025): which coding agent, which terminal, the prompt, and where your clones live.
struct AgentSettingsTab: View {
    @Bindable var model: AppModel
    @State private var scanning = false
    @State private var detected = false

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section("Agent") {
                Picker("Coding agent", selection: $prefs.agent) {
                    Text("Off").tag("")
                    ForEach(AgentLauncher.Agent.allCases) { a in
                        let installed = model.installedAgents.contains(a)
                        Text(installed || a == .custom ? a.title : "\(a.title) (not found)").tag(a.rawValue)
                            .selectionDisabled(!installed && a != .custom)
                    }
                }
                if prefs.agent == AgentLauncher.Agent.custom.rawValue {
                    TextField("Command, use {prompt} and {args}", text: $prefs.agentCustomCommand)
                        .font(.system(.body, design: .monospaced))
                }
                if let agent = AgentLauncher.Agent(rawValue: prefs.agent), !agent.permissionModes.isEmpty {
                    Picker("Permissions", selection: $prefs.agentPermissionMode) {
                        ForEach(agent.permissionModes, id: \.id) { Text($0.title).tag($0.id) }
                    }
                }
                TextField("Extra arguments (optional)", text: $prefs.agentExtraArgs)
                    .font(.system(.body, design: .monospaced))
                Picker("Open in", selection: $prefs.terminal) {
                    ForEach(AgentLauncher.Terminal.allCases) { t in
                        Text(t.isInstalled ? t.title : "\(t.title) (not installed)").tag(t.rawValue)
                            .selectionDisabled(!t.isInstalled)
                    }
                }
                Text("Permissions and extra arguments are passed to the agent's command as-is. With anything other than \"Ask every time\", the agent won't stop for approval, so you won't get a \"needs you\" notification.\n\nRow buttons hand a PR to this agent: Stoplight checks out the branch in a new worktree, opens your terminal there, and starts the agent with a prompt. Fix uses the failure; Adversarial review asks for findings. On a red followed branch (main is broken), Fix forks a fresh branch off it and asks for a PR. Your main checkout is never touched.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Fix prompt") {
                TextEditor(text: $prefs.promptTemplate)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                HStack {
                    Text("{number} {title} {repo} {branch} {base} {sha} {url} {failing_checks} {check_urls} {description}")
                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    Button("Reset") { prefs.promptTemplate = AgentLauncher.defaultPrompt }.controlSize(.small)
                }
            }
            Section("Review prompt") {
                TextEditor(text: $prefs.reviewTemplate)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                HStack {
                    Text("Used by the Adversarial review button (⇧⌘F). Same placeholders.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { prefs.reviewTemplate = AgentLauncher.defaultReviewPrompt }.controlSize(.small)
                }
            }
            Section("Repos") {
                HStack {
                    TextField("Folder to scan", text: $prefs.scanRoot).textFieldStyle(.roundedBorder)
                    Button(scanning ? "Scanning…" : "Scan") { scan() }.disabled(scanning)
                }
                if model.prefs.repoPaths.isEmpty {
                    Text("No clones found yet. Scan a folder that holds your git checkouts; remotes are matched to the PRs' repos.")
                        .foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(model.prefs.repoPaths.sorted(by: { $0.key < $1.key }), id: \.key) { slug, path in
                        HStack {
                            Text(slug)
                            Spacer()
                            Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Button { prefs.repoPaths[slug] = nil } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).help("Forget")
                        }
                    }
                }
                Text("A repo needs a local clone here before its PRs can be handed to the agent. Worktrees are created next to the clone as repo-branch; remove them with git worktree remove when you're done.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { if !detected { await model.detectAgents(); detected = true } }
    }

    private func scan() {
        scanning = true
        Task {
            let found = await AgentLauncher.scanRepos(root: model.prefs.scanRoot)
            model.prefs.repoPaths.merge(found) { _, new in new }
            scanning = false
        }
    }
}
