import AppKit
import Foundation
import SwiftUI
import UserNotifications

@main
struct CodexTowerApp: App {
    @StateObject private var dashboard = DashboardModel()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationCoordinator.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(dashboard)
                .frame(width: 430, height: 620)
        } label: {
            Label("Codex Tower", systemImage: dashboard.menuBarSymbol)
            if dashboard.needsAttentionCount > 0 { Text("\(dashboard.needsAttentionCount)") }
        }
        .menuBarExtraStyle(.window)
    }
}

private final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationCoordinator()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let sessionId = response.notification.request.content.userInfo["sessionId"] as? String,
              let url = URL(string: "codex://threads/\(sessionId)") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var tasks: [TowerTask] = []
    @Published private(set) var settings = TowerSettings()
    @Published private(set) var isSyncingHistory = false

    private let dataDirectory: URL
    private var refreshTimer: Timer?
    private var hasLoadedInitialTasks = false

    init() {
        dataDirectory = Self.resolveDataDirectory()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var needsAttentionCount: Int { tasks.filter { $0.needsAttention && !$0.isSnoozed }.count }
    var menuBarSymbol: String { needsAttentionCount > 0 ? "bell.badge.fill" : "building.2.fill" }
    var activeCount: Int { tasks.filter { $0.isActive && !$0.isSnoozed }.count }

    func visibleTasks(for filter: DashboardFilter) -> [TowerTask] {
        switch filter {
        case .all: return tasks
        case .needsAttention: return tasks.filter { $0.needsAttention && !$0.isSnoozed }
        case .active: return tasks.filter { $0.isActive && !$0.isSnoozed }
        case .completed: return tasks.filter { $0.status == .completed }
        case .history: return tasks.filter { $0.status == .history }
        }
    }

    func refresh() {
        let tasksURL = dataDirectory.appending(path: "tasks")
        let decoder = JSONDecoder()
        let loadedSettings = (try? Data(contentsOf: dataDirectory.appending(path: "settings.json")))
            .flatMap { try? decoder.decode(TowerSettings.self, from: $0) } ?? TowerSettings()
        let loadedTasks = ((try? FileManager.default.contentsOfDirectory(at: tasksURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(TowerTask.self, from: Data(contentsOf: $0)) }
        let archivedTasks = archiveExpiredCompletedTasks(loadedTasks)
            .sorted { $0.updatedAt > $1.updatedAt }

        if hasLoadedInitialTasks { notifyAboutStatusChanges(from: tasks, to: archivedTasks, settings: loadedSettings) }
        if archivedTasks != tasks { tasks = archivedTasks }
        if loadedSettings != settings { settings = loadedSettings }
        hasLoadedInitialTasks = true
    }

    func toggleMute() {
        settings.muted.toggle()
        saveSettings()
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

    func complete(_ task: TowerTask) {
        guard task.status != .completed else { return }
        var completedTask = task
        completedTask.status = .completed
        completedTask.completedAt = completedTask.completedAt ?? ISO8601DateFormatter().string(from: .now)
        completedTask.snoozedUntil = nil
        saveTask(completedTask)
        playCompletionSoundIfNeeded()
        refresh()
    }

    func snooze(_ task: TowerTask) {
        guard task.needsAttention else { return }
        var snoozedTask = task
        snoozedTask.snoozedUntil = ISO8601DateFormatter().string(from: .now.addingTimeInterval(60 * 60))
        saveTask(snoozedTask)
        refresh()
    }

    func syncHistory() {
        guard !isSyncingHistory,
              let script = Bundle.main.url(forResource: "sync-existing", withExtension: "mjs") else { return }
        isSyncingHistory = true
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["node", script.path]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.isSyncingHistory = false; self?.refresh() }
        }
        do { try process.run() } catch {
            isSyncingHistory = false
            NSLog("Codex Tower could not sync history: \(error.localizedDescription)")
        }
    }

    private func markViewed(_ task: TowerTask) {
        guard task.status == .awaitingReview else { return }
        var viewedTask = task
        viewedTask.status = .reviewed
        viewedTask.viewedAt = ISO8601DateFormatter().string(from: .now)
        saveTask(viewedTask)
        refresh()
    }

    private func archiveExpiredCompletedTasks(_ loadedTasks: [TowerTask]) -> [TowerTask] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return loadedTasks.map { task in
            guard task.status == .completed,
                  let completedAt = task.completedDate,
                  completedAt < cutoff else { return task }
            var archivedTask = task
            archivedTask.status = .history
            archivedTask.archivedAt = ISO8601DateFormatter().string(from: .now)
            saveTask(archivedTask)
            return archivedTask
        }
    }

    private func notifyAboutStatusChanges(from previousTasks: [TowerTask], to nextTasks: [TowerTask], settings: TowerSettings) {
        guard !settings.muted else { return }
        let previousStatuses = Dictionary(uniqueKeysWithValues: previousTasks.map { ($0.sessionId, $0.status) })
        for task in nextTasks where task.status.shouldNotify && previousStatuses[task.sessionId] != task.status {
            let content = UNMutableNotificationContent()
            content.title = task.status.notificationTitle
            content.body = task.title
            content.userInfo = ["sessionId": task.sessionId]
            let request = UNNotificationRequest(identifier: "codex-tower-\(task.sessionId)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func saveSettings() {
        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try JSONEncoder.pretty.encode(settings).write(to: dataDirectory.appending(path: "settings.json"), options: .atomic)
        } catch { NSLog("Codex Tower could not save settings: \(error.localizedDescription)") }
    }

    private func saveTask(_ task: TowerTask) {
        do {
            let taskDirectory = dataDirectory.appending(path: "tasks")
            try FileManager.default.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
            try JSONEncoder.pretty.encode(task).write(to: taskDirectory.appending(path: "\(task.sessionId).json"), options: .atomic)
        } catch { NSLog("Codex Tower could not save task: \(error.localizedDescription)") }
    }

    private func playCompletionSoundIfNeeded() {
        guard !settings.muted else { return }
        NSSound(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/\(settings.sounds.complete).aiff"), byReference: false)?.play()
    }

    private static func resolveDataDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_TOWER_DATA_DIR"], !override.isEmpty { return URL(filePath: override) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Codex Tower")
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
                    .buttonStyle(.borderless).accessibilityLabel(Copy.refresh)
            }
            .padding()
            Divider()

            Picker(Copy.filter, selection: $filter) {
                ForEach(DashboardFilter.allCases) { option in Text(option.label).tag(option) }
            }
            .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 10)

            if dashboard.visibleTasks(for: filter).isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "building.2.fill").font(.largeTitle).foregroundStyle(.secondary)
                    Text(Copy.emptyTitle).font(.headline)
                    Text(Copy.emptyBody).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(dashboard.visibleTasks(for: filter)) { task in
                            TaskRow(task: task, onOpen: { dashboard.openThread(task) }, onComplete: { dashboard.complete(task) }, onSnooze: { dashboard.snooze(task) })
                        }
                    }
                    .padding()
                }
            }

            Divider()
            HStack {
                Button(dashboard.settings.muted ? Copy.unmute : Copy.mute) { dashboard.toggleMute() }
                Button(dashboard.isSyncingHistory ? Copy.syncing : Copy.syncHistory) { dashboard.syncHistory() }.disabled(dashboard.isSyncingHistory)
                Button(Copy.showData) { dashboard.showDataDirectory() }
                Spacer()
                Button(Copy.quit) { NSApplication.shared.terminate(nil) }
            }
            .padding()
        }
    }

    private var summary: String {
        if dashboard.needsAttentionCount > 0 { return Copy.attentionSummary(dashboard.needsAttentionCount) }
        if dashboard.activeCount > 0 { return Copy.activeSummary(dashboard.activeCount) }
        return Copy.allCaughtUp
    }
}

private struct TaskRow: View {
    let task: TowerTask
    let onOpen: () -> Void
    let onComplete: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title).lineLimit(2).font(.body.weight(.semibold))
                    HStack(spacing: 8) {
                        Text(task.updatedAt.relativeDescription)
                        if let projectName = task.projectName { Text(projectName).lineLimit(1) }
                        if task.totalSteps > 0 { Text("\(task.completedSteps)/\(task.totalSteps) \(Copy.steps)") }
                        if task.subagentCount > 0 { Text("\(task.subagentCount) \(Copy.agents)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if let reason = task.waitingReason, !reason.isEmpty { Text(reason).lineLimit(1).font(.caption).foregroundStyle(.orange) }
                    if task.isSnoozed { Text(Copy.snoozed).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain).accessibilityLabel(Copy.openTask(task.title))

            VStack(alignment: .trailing, spacing: 8) {
                StatusPill(status: task.status)
                HStack(spacing: 6) {
                    if task.needsAttention && !task.isSnoozed {
                        Button(Copy.later, action: onSnooze).buttonStyle(.bordered)
                        Button(Copy.done, action: onComplete).buttonStyle(.borderedProminent)
                    } else {
                        Button(Copy.open, action: onOpen).buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct StatusPill: View {
    let status: TaskStatus
    var body: some View {
        Label(status.label, systemImage: status.symbol).font(.caption2.weight(.semibold)).foregroundStyle(status.tint)
            .padding(.horizontal, 7).padding(.vertical, 4).background(status.tint.opacity(0.13), in: Capsule())
    }
}

enum DashboardFilter: String, CaseIterable, Identifiable {
    case active, needsAttention, completed, history, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .active: Copy.active
        case .needsAttention: Copy.attention
        case .completed: Copy.done
        case .history: Copy.history
        case .all: Copy.all
        }
    }
}

enum TaskStatus: String, Codable {
    case ready, running
    case waitingForYou = "waiting_for_you"
    case awaitingReview = "awaiting_review"
    case reviewed, completed, closed, history

    var label: String {
        switch self {
        case .ready: Copy.ready
        case .running: Copy.running
        case .waitingForYou: Copy.waiting
        case .awaitingReview: Copy.awaitingReview
        case .reviewed: Copy.reviewed
        case .completed: Copy.completed
        case .closed: Copy.closed
        case .history: Copy.history
        }
    }
    var symbol: String {
        ["ready": "circle.dashed", "running": "arrow.triangle.2.circlepath", "waiting_for_you": "hand.raised.fill", "awaiting_review": "eye.fill", "reviewed": "eye.circle.fill", "completed": "checkmark.circle.fill", "closed": "archivebox.fill", "history": "clock.arrow.circlepath"][rawValue] ?? "circle"
    }
    var tint: Color {
        ["ready": .secondary, "running": .blue, "waiting_for_you": .orange, "awaiting_review": .yellow, "reviewed": .secondary, "completed": .green, "closed": .secondary, "history": .secondary][rawValue] ?? .secondary
    }
    var shouldNotify: Bool { self == .waitingForYou || self == .awaitingReview || self == .completed }
    var notificationTitle: String {
        switch self {
        case .waitingForYou: Copy.notificationApproval
        case .awaitingReview: Copy.notificationReview
        case .completed: Copy.notificationComplete
        default: "Codex Tower"
        }
    }
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
    var completedAt: String?
    var snoozedUntil: String?
    var archivedAt: String?
    var id: String { sessionId }
    var subagentCount: Int { subagents?.count ?? 0 }
    var completedDate: Date? { completedAt.flatMap { ISO8601DateFormatter().date(from: $0) } }
    var snoozedDate: Date? { snoozedUntil.flatMap { ISO8601DateFormatter().date(from: $0) } }
    var isSnoozed: Bool { (snoozedDate ?? .distantPast) > .now }
    var needsAttention: Bool { status == .waitingForYou || status == .awaitingReview }
    var isActive: Bool { [.ready, .running, .waitingForYou, .awaitingReview].contains(status) }
    var projectName: String? { guard let cwd, !cwd.isEmpty else { return nil }; return URL(filePath: cwd).lastPathComponent }
}

struct Subagent: Codable, Equatable { let type: String; let status: String; let updatedAt: String }
struct TowerSettings: Codable, Equatable {
    var muted = false
    var sounds = Sounds()
    struct Sounds: Codable, Equatable { var attention = "Glass"; var complete = "Hero"; var blocked = "Basso" }
}

private enum Copy {
    private static var chinese: Bool { Locale.current.language.languageCode?.identifier == "zh" }
    private static func text(_ english: String, _ chinese: String) -> String { self.chinese ? chinese : english }
    static let refresh = text("Refresh tasks", "刷新任务")
    static let filter = text("Task filter", "任务筛选")
    static let emptyTitle = text("No tasks in this view", "此视图暂无任务")
    static let emptyBody = text("Start a Codex task after trusting the Codex Tower hooks.", "信任 Codex Tower hooks 后，开始一个 Codex 任务即可显示。")
    static let unmute = text("Unmute", "取消静音")
    static let mute = text("Mute", "静音")
    static let syncing = text("Syncing…", "同步中…")
    static let syncHistory = text("Sync history", "同步历史")
    static let showData = text("Show data", "显示数据")
    static let quit = text("Quit", "退出")
    static let later = text("Later", "稍后")
    static let done = text("Done", "完成")
    static let open = text("Open", "打开")
    static let snoozed = text("Snoozed for one hour", "已延后一小时")
    static let steps = text("steps", "步")
    static let agents = text("agents", "个代理")
    static let active = text("Active", "进行中")
    static let attention = text("Attention", "待处理")
    static let history = text("History", "历史")
    static let all = text("All", "全部")
    static let ready = text("Ready", "已就绪")
    static let running = text("Running", "进行中")
    static let waiting = text("Waiting for you", "等待你处理")
    static let awaitingReview = text("Awaiting review", "待验收")
    static let reviewed = text("Viewed", "已查看")
    static let completed = text("Completed", "已完成")
    static let closed = text("Closed", "已关闭")
    static let allCaughtUp = text("All caught up · newest first", "全部已处理 · 最新优先")
    static let notificationApproval = text("Codex needs your approval", "Codex 需要你的确认")
    static let notificationReview = text("A task is ready for review", "有任务等待验收")
    static let notificationComplete = text("Task completed", "任务已完成")
    static let updatedRecently = text("Updated recently", "刚刚更新")
    static func attentionSummary(_ count: Int) -> String { text("\(count) task(s) need attention", "有 \(count) 个任务待处理") }
    static func activeSummary(_ count: Int) -> String { text("\(count) task(s) active · newest first", "有 \(count) 个任务进行中 · 最新优先") }
    static func openTask(_ title: String) -> String { text("Open \(title) in Codex", "在 Codex 中打开 \(title)") }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}

private extension String {
    var relativeDescription: String {
        guard let date = ISO8601DateFormatter().date(from: self) else { return Copy.updatedRecently }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}
