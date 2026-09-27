import MindSpaceCore
import SwiftUI

struct StructuredTaskView: View {
    @ObservedObject var model: MindSpaceAppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 218)
            Divider().overlay(.white.opacity(0.06))
            content
        }
        .padding(18)
        .glassPanel(cornerRadius: 24)
        .padding(22)
        .sheet(isPresented: $model.isCreatingProject) {
            NewProjectView(model: model)
        }
        .accessibilityIdentifier("structuredTaskRoot")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MIND SPACE")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(.white.opacity(0.44))
                    Text("Make room for what matters.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.32))
                }
                Spacer()
            }

            VStack(spacing: 4) {
                ForEach(MindSpaceAppModel.Section.allCases) { section in
                    Button {
                        model.selectedSection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).frame(width: 18)
                            Text(section.rawValue)
                            Spacer()
                            if section == .today, !model.visibleTasks.isEmpty, model.selectedSection == .today {
                                Text("\(model.visibleTasks.count)").font(.caption2).opacity(0.5)
                            }
                        }
                        .font(.system(size: 13, weight: model.selectedSection == section ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(model.selectedSection == section ? 0.92 : 0.56))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            model.selectedSection == section ? Color.white.opacity(0.075) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if model.pendingLogCount > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Vault needs attention", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                    Text("\(model.pendingLogCount) event(s) waiting")
                        .font(.caption2)
                        .opacity(0.55)
                }
                .foregroundStyle(.orange.opacity(0.86))
                .padding(11)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            }

            Button {
                model.returnToMindSpace()
            } label: {
                Label("Mind Space", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(18)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selectedSection.rawValue)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                    Text(sectionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
                if model.selectedSection == .projects {
                    Button("New Project") { model.isCreatingProject = true }
                        .buttonStyle(.bordered)
                }
                Button {
                    model.isPresentingNewTask = true
                } label: {
                    Label("Add Task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.70, green: 0.29, blue: 0.13))
                .accessibilityIdentifier("addTaskButton")
            }
            .padding(22)

            Divider().overlay(.white.opacity(0.06))

            switch model.selectedSection {
            case .logbook:
                logbook
            case .settings:
                settings
            case .projects:
                projects
            default:
                taskList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskList: some View {
        Group {
            if model.visibleTasks.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: model.selectedSection.symbol)
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if model.selectedSection != .done {
                        Button("Add a Task") { model.isPresentingNewTask = true }
                    }
                }
                .foregroundStyle(.white.opacity(0.62))
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(model.visibleTasks, id: \.id) { task in
                            TaskRow(model: model, task: task)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private var projects: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 13)], spacing: 13) {
                    ForEach(model.projects, id: \.id) { project in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "cube.transparent")
                                    .foregroundStyle(projectColor(project.colorToken))
                                Spacer()
                                Text("\(openTaskCount(project.id)) open")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            HStack(spacing: 8) {
                                Text(project.name)
                                    .font(.headline)
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                                Button {
                                    model.editingProject = project
                                } label: {
                                    Label("Manage", systemImage: "slider.horizontal.3")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white.opacity(0.42))
                                .help("Manage \(project.name)")
                            }
                            ForEach(model.tasks.filter { $0.projectID == project.id && $0.status != .completed && $0.status != .trashed }.prefix(3), id: \.id) { task in
                                Button(task.title) { model.selectedTask = task }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }
                        .padding(16)
                        .glassPanel(cornerRadius: 15)
                        .overlay {
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(
                                    model.selectedProjectID == project.id ? Color.orange.opacity(0.72) : .clear,
                                    lineWidth: 1.5
                                )
                        }
                        .id(project.id)
                        .onTapGesture { model.selectedProjectID = project.id }
                    }
                }
                .padding(18)
            }
            .onAppear { scrollToSelectedProject(using: proxy) }
            .onChange(of: model.selectedProjectID) { _, _ in scrollToSelectedProject(using: proxy) }
        }
    }

    private func scrollToSelectedProject(using proxy: ScrollViewProxy) {
        guard let projectID = model.selectedProjectID else { return }
        withAnimation(.easeOut(duration: 0.28)) {
            proxy.scrollTo(projectID, anchor: .center)
        }
    }

    private var logbook: some View {
        VStack(spacing: 15) {
            Image(systemName: "book.pages").font(.system(size: 38, weight: .light))
            Text("Append-only task history")
                .font(.title3.weight(.medium))
            Text(model.preferences.vaultPath ?? "Choose an Obsidian vault in Settings to begin logging.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if let message = model.vaultMessage {
                Text(message).font(.caption).foregroundStyle(.orange.opacity(0.8))
            }
            if model.pendingLogCount > 0 {
                Button("Retry \(model.pendingLogCount) Pending Event(s)") {
                    try? model.retryPendingLogs()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white.opacity(0.78))
    }

    private var settings: some View {
        Form {
            Section("Obsidian Vault") {
                LabeledContent("Location", value: model.preferences.vaultPath ?? "Not configured")
                HStack {
                    Button("Choose Vault…") { model.chooseVault() }
                    if model.pendingLogCount > 0 {
                        Button("Retry Pending Logs") { try? model.retryPendingLogs() }
                    }
                }
                if let message = model.vaultMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Motion") {
                Toggle(
                    "Reduce spatial motion",
                    isOn: Binding(
                        get: { model.preferences.reducedMotion },
                        set: { model.setReducedMotion($0) }
                    )
                )
                Text("Shortens or removes drifting and the Make It Make Sense transformation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local Data") {
                Text("Tasks and projects stay on this Mac in MindSpace.store. No account or network connection is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(8)
    }

    private var sectionSubtitle: String {
        switch model.selectedSection {
        case .today: "A deliberately short list for right now."
        case .inbox: "Captured first. Organised when you are ready."
        case .projects: "Longer threads gathered into calm containers."
        case .done: "Finished thoughts, kept without clutter."
        case .trash: "Recoverable tasks stay here until you restore them."
        case .logbook: "Your readable activity trail in Obsidian."
        case .settings: "Local preferences and vault access."
        }
    }

    private var emptyTitle: String {
        switch model.selectedSection {
        case .today: "Nothing chosen for Today"
        case .inbox: "Inbox is clear"
        case .done: "Nothing completed yet"
        default: "Nothing here yet"
        }
    }

    private var emptyDescription: String {
        switch model.selectedSection {
        case .today: "Choose a task from Inbox or capture what matters now."
        case .inbox: "New unassigned thoughts will land here."
        case .done: "Completed tasks will collect here quietly."
        default: "Capture a thought to begin."
        }
    }

    private func openTaskCount(_ projectID: String) -> Int {
        model.tasks.filter { $0.projectID == projectID && $0.status != .completed && $0.status != .trashed }.count
    }

    private func projectColor(_ token: String) -> Color {
        switch token.lowercased() {
        case "orange": .orange
        case "purple": .purple
        case "green": .green
        default: .blue
        }
    }
}

private struct TaskRow: View {
    @ObservedObject var model: MindSpaceAppModel
    let task: MindSpaceTask

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if task.status == .trashed {
                    model.restore(task)
                } else if task.status == .completed {
                    model.reopen(task)
                } else {
                    model.complete(task)
                }
            } label: {
                Image(systemName: actionSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(actionColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionLabel)

            Button {
                model.selectedTask = task
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(task.status == .completed ? 0.44 : 0.9))
                        .strikethrough(task.status == .completed, color: .white.opacity(0.3))
                    HStack(spacing: 8) {
                        if let project = model.project(for: task) {
                            Text(project.name)
                        } else {
                            Text("Inbox")
                        }
                        if let category = task.category { Text("• \(category)") }
                        if let dueDate = task.dueDate { Text("• \(dueDate.formatted(date: .abbreviated, time: .omitted))") }
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.34))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                model.toggleToday(task)
            } label: {
                Image(systemName: task.isToday ? "sun.max.fill" : "sun.max")
                    .foregroundStyle(task.isToday ? .orange.opacity(0.82) : .white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .help(task.isToday ? "Remove from Today" : "Add to Today")
            .disabled(task.status == .trashed)

            Menu {
                if task.status == .trashed {
                    Button("Restore") { model.restore(task) }
                } else {
                    Button("Edit") { model.selectedTask = task }
                    Button("Delete", role: .destructive) { model.delete(task) }
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.white.opacity(0.35))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.045), lineWidth: 1))
    }

    private var actionSymbol: String {
        switch task.status {
        case .completed: "checkmark.circle.fill"
        case .trashed: "arrow.uturn.backward.circle"
        case .inbox, .active: "circle"
        }
    }

    private var actionColor: Color {
        switch task.status {
        case .completed: .green.opacity(0.72)
        case .trashed: Color(red: 0.78, green: 0.31, blue: 0.13)
        case .inbox, .active: .white.opacity(0.32)
        }
    }

    private var actionLabel: String {
        switch task.status {
        case .completed: "Reopen \(task.title)"
        case .trashed: "Restore \(task.title)"
        case .inbox, .active: "Complete \(task.title)"
        }
    }
}

private final class NewProjectFormModel: ObservableObject {
    @Published var name = ""
    @Published var colorToken = "cobalt"
}

private struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MindSpaceAppModel
    @ObservedObject private var form: NewProjectFormModel

    init(model: MindSpaceAppModel) {
        self.model = model
        _form = ObservedObject(wrappedValue: NewProjectFormModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Project").font(.title2.weight(.medium))
            TextField("Project name", text: $form.name)
            Picker("Accent", selection: $form.colorToken) {
                Text("Cobalt").tag("cobalt")
                Text("Purple").tag("purple")
                Text("Green").tag("green")
                Text("Orange").tag("orange")
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    model.createProject(name: form.name, colorToken: form.colorToken)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
