import MindSpaceCore
import SwiftUI

private final class ProjectGalaxyFormModel: ObservableObject {
    @Published var name: String
    @Published var colorToken: String
    @Published var memberTaskIDs: Set<String>
    @Published var isConfirmingDissolve = false

    init(project: MindSpaceProject, tasks: [MindSpaceTask]) {
        name = project.name
        colorToken = project.colorToken
        memberTaskIDs = Set(tasks.filter { $0.projectID == project.id }.map(\.id))
    }
}

struct ProjectGalaxyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MindSpaceAppModel
    let project: MindSpaceProject
    @ObservedObject private var form: ProjectGalaxyFormModel

    init(model: MindSpaceAppModel, project: MindSpaceProject) {
        self.model = model
        self.project = project
        _form = ObservedObject(wrappedValue: ProjectGalaxyFormModel(project: project, tasks: model.tasks))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Manage Galaxy")
                    .font(.title2.weight(.medium))
                Text("Changes here stay synchronized with Mind Space and the structured project view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Project name", text: $form.name)
                .textFieldStyle(.roundedBorder)

            Picker("Galaxy colour", selection: $form.colorToken) {
                Text("Cobalt").tag("cobalt")
                Text("Purple").tag("purple")
                Text("Green").tag("green")
                Text("Orange").tag("orange")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Thoughts in this galaxy")
                    .font(.headline)
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(eligibleTasks, id: \.id) { task in
                            Toggle(isOn: membershipBinding(for: task.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .foregroundStyle(.primary)
                                    Text(task.projectID == nil ? "Ungrouped" : projectName(for: task))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 310)
            }

            HStack {
                Button("Dissolve Galaxy", role: .destructive) {
                    form.isConfirmingDissolve = true
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Changes") {
                    if model.updateProject(
                        project,
                        name: form.name,
                        colorToken: form.colorToken,
                        memberTaskIDs: form.memberTaskIDs
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange.opacity(0.78))
                .disabled(form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 540)
        .alert("Dissolve \(project.name)?", isPresented: $form.isConfirmingDissolve) {
            Button("Cancel", role: .cancel) {}
            Button("Dissolve", role: .destructive) {
                if model.dissolveProject(project) {
                    dismiss()
                }
            }
        } message: {
            Text("The project will be archived. Its tasks will remain intact and return to Inbox.")
        }
    }

    private var eligibleTasks: [MindSpaceTask] {
        model.tasks.filter { $0.status == .inbox || $0.status == .active }
    }

    private func membershipBinding(for taskID: String) -> Binding<Bool> {
        Binding(
            get: { form.memberTaskIDs.contains(taskID) },
            set: { isMember in
                if isMember {
                    form.memberTaskIDs.insert(taskID)
                } else {
                    form.memberTaskIDs.remove(taskID)
                }
            }
        )
    }

    private func projectName(for task: MindSpaceTask) -> String {
        model.project(for: task)?.name ?? "Ungrouped"
    }
}
