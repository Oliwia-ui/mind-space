import SwiftUI

private final class NewGalaxyFormModel: ObservableObject {
    @Published var name = ""
    @Published var colorToken = "purple"
}

struct NewGalaxyView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MindSpaceAppModel
    @ObservedObject private var form: NewGalaxyFormModel

    init(model: MindSpaceAppModel) {
        self.model = model
        _form = ObservedObject(wrappedValue: NewGalaxyFormModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name this galaxy")
                    .font(.title2.weight(.medium))
                Text("The original thoughts remain separate, editable tasks inside one real project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(groupedTaskTitles, id: \.self) { title in
                    Label(title, systemImage: "sparkles")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.06), in: Capsule())
                }
            }

            TextField("Galaxy or project name", text: $form.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("galaxyNameField")

            Picker("Galaxy colour", selection: $form.colorToken) {
                Text("Cobalt").tag("cobalt")
                Text("Purple").tag("purple")
                Text("Green").tag("green")
                Text("Orange").tag("orange")
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancelGalaxyCreation()
                    dismiss()
                }
                Button("Create Galaxy") {
                    if model.createGalaxy(name: form.name, colorToken: form.colorToken) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange.opacity(0.78))
                .disabled(form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("createGalaxyButton")
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var groupedTaskTitles: [String] {
        model.pendingGalaxyTaskIDs.compactMap { taskID in
            model.tasks.first(where: { $0.id == taskID })?.title
        }
    }
}
