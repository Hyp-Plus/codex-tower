import AppKit
import Foundation
import SwiftUI

@main
struct CodexTowerApp: App {
    @StateObject private var dashboard = DashboardModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(dashboard)
                .frame(width: 430, height: 620)
        } label: {
            Label("Codex Tower", systemImage: dashboard.menuBarSymbol)
            if dashboard.needsAttentionCount > 0 {
                Text("\(dashboard.needsAttentionCount)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var tasks: [TowerTask] = []
    @Published private(set) var settings = TowerSettings()
    @Published private(set) var isSyncingHistory = false

    private let dataDirectory: URL
    private var refreshTimer: Timer?

    init() {
        dataDirectory = Self.resolveDataDirectory()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var needsAttentionCount: Int {
        tasks.filter { $0.status == .waitingForYou || $0.status == .awaitingReview }.count
    }

    var menuBarSymbol: String {
        needsAttentionCount > 0 ? "bell.badge.fill" : "building.2.fill"
    }

    var activeCount: Int {
        tasks.filter { [.running, .waitingForYou, .awaitingReview].contains($0.status) }.count
    }

    func visibleTasks(for filter: DashboardFilter) -> [TowerTask] {
        switch filter {
        case .all: return tasks
        case .needsAttention: return tasks.filter { [.waitingForYou, .awaitingReview].contains($0.status) }
        case .active: return tasks.filter { [.running, .waitingForYou, .awaitingReview].contains($0.status) }
        case .history: return tasks.filter { $0.status == .history }
        }
    }

    func refresh() {
        let tasksURL = dataDirectory.appending(path: "tasks")
        let decoder = JSONDecoder()
        let loadedTasks = (try? FileManager.default.contentsOfDirectory(at: tasksURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(TowerTask.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt } ?? []
        let loadedSettings = (try? Data(contentsOf: dataDirectory.appending(path: "settings.json")))
            .flatMap { try? decoder.decode(TowerSettings.self, from: $0) } ?? TowerSettings()

        if loadedTasks != tasks { tasks = loadedTasks }
        if loadedSettings != settings { settings = loadedSettings }
    }

    func toggleMute() {
        settings.muted.toggle()
        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(settings)
            try data.write(to: dataDirectory.appending(path: "settings.json"), options: .atomic)
        } catch {
            NSLog("Codex Tower could not save settings: \(error.localizedDescription)")
        }
    }

    func showDataDirectory() {
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dataDirectory])
    }

    func openThread(_ task: TowerTask) {
        markViewed(task)
        guard let url = URL(string: "codex://threads/\(task.sessionId)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func markViewed(_ task: TowerTask) {
        guard task.status == .awaitingReview,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var viewedTask = task
        viewedTask.status = .reviewed
        viewedTask.viewedAt = ISO8601DateFormatter().string(from: .now)
        tasks[index] = viewedTask

        do {
            let taskDirectory = dataDirectory.appending(path: "tasks")
            try FileManager.default.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(viewedTask)
            try data.write(to: taskDirectory.appending(path: "\(task.sessionId).json"), options: .atomic)
        } catch {
            NSLog("Codex Tower could not record task view: \(error.localizedDescription)")
            refresh()
        }
    }

    func syncHistory() {
        guard !isSyncingHistory,
              let script = Bundle.main.url(forResource: "sync-existing", withExtension: "mjs") else { return }
        isSyncingHistory = true
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["node", script.path]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isSyncingHistory = false
                self?.refresh()
            }
        }
        do { try process.run() } catch {
            isSyncingHistory = false
            NSLog("Codex Tower could not sync history: \(error.localizedDescription)")
        }
    }

    private static func resolveDataDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_TOWER_DATA_DIR"], !override.isEmpty {
            return URL(filePath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Codex Tower")
    }
}

struct DashboardView: View {
    @EnvironmentObject private var dashboard: DashboardModel
    @State private var filter: DashboardFilter = .active

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: "building.2.fill").foregroundStyle(.tint)
                        Text("Codex Tower").font(.title2.bold())
                    }
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: dashboard.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh tasks")
            }
            .padding()

            Divider()

            Picker("Task filter", selection: $filter) {
                ForEach(DashboardFilter.allCases) { option in Text(option.label).tag(option) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)

            if dashboard.tasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "building.2.fill").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No local tasks yet").font(.headline)
                    Text("Start a new Codex task after trusting the Codex Tower hooks.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(dashboard.visibleTasks(for: filter)) { task in
                            Button { dashboard.openThread(task) } label: { TaskRow(task: task) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open \(task.title) in Codex")
                        }
                    }
                    .padding()
                }
            }

            Divider()
            HStack {
                Button(dashboard.settings.muted ? "Unmute" : "Mute") { dashboard.toggleMute() }
                Button(dashboard.isSyncingHistory ? "Syncing…" : "Sync history") { dashboard.syncHistory() }
                    .disabled(dashboard.isSyncingHistory)
                Button("Show data") { dashboard.showDataDirectory() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding()
        }
    }

    private var summary: String {
        if dashboard.needsAttentionCount > 0 { return "\(dashboard.needsAttentionCount) task(s) need attention" }
        if dashboard.activeCount > 0 { return "\(dashboard.activeCount) task(s) active · newest first" }
        return "All caught up · newest first"
    }
}

private struct TaskRow: View {
    let task: TowerTask

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text(task.title).lineLimit(2).font(.body.weight(.semibold))
                HStack(spacing: 8) {
                    Text(task.updatedAt.relativeDescription)
                    if let projectName = task.projectName { Text(projectName).lineLimit(1) }
                    if task.totalSteps > 0 { Text("\(task.completedSteps)/\(task.totalSteps) steps") }
                    if task.subagentCount > 0 { Text("\(task.subagentCount) agents") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let reason = task.waitingReason, !reason.isEmpty {
                    Text(reason).lineLimit(1).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                StatusPill(status: task.status)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct StatusPill: View {
    let status: TaskStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.13), in: Capsule())
    }
}

enum DashboardFilter: String, CaseIterable, Identifiable {
    case all
    case needsAttention
    case active
    case history

    var id: String { rawValue }
    var label: String { ["all": "All", "needsAttention": "Attention", "active": "Active", "history": "History"][rawValue] ?? rawValue }
}

enum TaskStatus: String, Codable {
    case running
    case waitingForYou = "waiting_for_you"
    case awaitingReview = "awaiting_review"
    case reviewed
    case completed
    case closed
    case history

    var label: String { ["running": "Running", "waiting_for_you": "Waiting for you", "awaiting_review": "Awaiting review", "reviewed": "Viewed", "completed": "Completed", "closed": "Closed", "history": "History"][rawValue] ?? rawValue }
    var symbol: String { ["running": "arrow.triangle.2.circlepath", "waiting_for_you": "hand.raised.fill", "awaiting_review": "eye.fill", "reviewed": "eye.circle.fill", "completed": "checkmark.circle.fill", "closed": "archivebox.fill", "history": "clock.arrow.circlepath"][rawValue] ?? "circle" }
    var tint: Color { ["running": .blue, "waiting_for_you": .orange, "awaiting_review": .yellow, "reviewed": .secondary, "completed": .green, "closed": .secondary, "history": .secondary][rawValue] ?? .secondary }
}

struct TowerTask: Codable, Identifiable, Equatable {
    let sessionId: String
    let title: String
    var status: TaskStatus
    let updatedAt: String
    let completedSteps: Int
    let totalSteps: Int
    let waitingReason: String?
    let subagents: [String: Subagent]?
    let cwd: String?
    var viewedAt: String?
    var id: String { sessionId }
    var subagentCount: Int { subagents?.count ?? 0 }
    var projectName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(filePath: cwd).lastPathComponent
    }
}

struct Subagent: Codable, Equatable { let type: String; let status: String; let updatedAt: String }

struct TowerSettings: Codable, Equatable {
    var muted = false
    var sounds = Sounds()
    struct Sounds: Codable, Equatable { var attention = "Glass"; var complete = "Hero"; var blocked = "Basso" }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}

private extension String {
    var relativeDescription: String {
        guard let date = ISO8601DateFormatter().date(from: self) else { return "Updated recently" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}
