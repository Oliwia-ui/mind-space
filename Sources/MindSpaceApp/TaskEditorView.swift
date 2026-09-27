import MindSpaceCore
import SwiftUI

private final class TaskEditorFormModel: ObservableObject {
    @Published var title: String
    @Published var notes: String
    @Published var projectID: String?
    @Published var hasDueDate: Bool
    @Published var dueDate: Date
    @Published var category: String
    @Published var energy: String
    @Published var isToday: Bool
    @Published var confirmsDeletion = false

    init(task: MindSpaceTask?) {
        title = task?.title ?? ""
        notes = task?.notes ?? ""
        projectID = task?.projectID
        hasDueDate = task?.dueDate != nil
        dueDate = task?.dueDate ?? Date()
        category = task?.category ?? ""
        energy = task?.energy ?? ""
        isToday = task?.isToday ?? false
    }
}

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MindSpaceAppModel
    @ObservedObject private var form: TaskEditorFormModel

    private let existingTask: MindSpaceTask?

    init(model: MindSpaceAppModel, task: MindSpaceTask?) {
        self.model = model
        existingTask = task
        _form = ObservedObject(wrappedValue: TaskEditorFormModel(task: task))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(existingTask == nil ? "Capture a Thought" : "Task Details")
                        .font(.title2.weight(.medium))
                    Text(existingTask == nil ? "It can be organised later." : existingTask?.id ?? "")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button(existingTask == nil ? "Cancel" : "Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelTaskEditorButton")
                Button("Done") { saveAndDismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.70, green: 0.29, blue: 0.13))
                    .disabled(form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(22)

            Divider()

            Form {
                Section("Task") {
                    TextField("What needs your attention?", text: $form.title)
                        .font(.headline)
                    TextField("Notes", text: $form.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Place") {
                    Picker("Project", selection: $form.projectID) {
                        Text("Inbox").tag(String?.none)
                        ForEach(model.projects, id: \.id) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    Toggle("Today", isOn: $form.isToday)
                }

                Section("Context") {
                    TextField("Category, e.g. idea or university", text: $form.category)
                    Picker("Energy", selection: $form.energy) {
                        Text("Not set").tag("")
                        Text("Low").tag("low")
                        Text("Steady").tag("steady")
                        Text("High").tag("high")
                    }
                    Toggle("Due date", isOn: $form.hasDueDate)
                    if form.hasDueDate {
                        DatePicker("Date", selection: $form.dueDate, displayedComponents: .date)
                    }
                }
            }
            .formStyle(.grouped)

            if let task = existingTask {
                Divider()
                HStack {
                    if task.status == .completed {
                        Button("Reopen") {
                            model.reopen(task)
                            dismiss()
                        }
                    } else {
                        Button("Mark Complete") {
                            model.complete(task)
                            dismiss()
                        }
                    }
                    Spacer()
                    Button("Move to Trash", role: .destructive) {
                        form.confirmsDeletion = true
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 520, height: 650)
        .confirmationDialog(
            "Move this task to recoverable Trash?",
            isPresented: $form.confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let task = existingTask { model.delete(task) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The task remains stored locally and can be restored later.")
        }
    }

    private func saveAndDismiss() {
        let cleanTitle = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = form.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = form.category.trimmingCharacters(in: .whitespacesAndNewlines)

        if var task = existingTask {
            task.title = cleanTitle
            task.notes = cleanNotes.isEmpty ? nil : cleanNotes
            task.projectID = form.projectID
            if task.status == .inbox, form.projectID != nil { task.status = .active }
            if task.status == .active, form.projectID == nil { task.status = .inbox }
            task.dueDate = form.hasDueDate ? form.dueDate : nil
            task.category = cleanCategory.isEmpty ? nil : cleanCategory
            task.energy = form.energy.isEmpty ? nil : form.energy
            task.isToday = form.isToday
            if model.updateTask(task) { dismiss() }
        } else {
            let saved = model.createTask(
                title: cleanTitle,
                notes: cleanNotes.isEmpty ? nil : cleanNotes,
                projectID: form.projectID,
                dueDate: form.hasDueDate ? form.dueDate : nil,
                category: cleanCategory.isEmpty ? nil : cleanCategory,
                energy: form.energy.isEmpty ? nil : form.energy,
                isToday: form.isToday
            )
            if saved { dismiss() }
        }
    }
}
