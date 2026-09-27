import MindSpaceCore
import SwiftUI

struct MindSpaceCanvasView: View {
    @ObservedObject var model: MindSpaceAppModel

    private var openTasks: [MindSpaceTask] {
        Array(model.tasks.filter { $0.status != .completed && $0.status != .trashed }.prefix(10))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                orbitalGuides(in: geometry.size)

                VStack(spacing: 8) {
                    Text("MIND SPACE")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(3.4)
                        .foregroundStyle(.white.opacity(0.48))
                    Text("Your thoughts, still in motion.")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .position(x: geometry.size.width / 2, y: 72)

                ForEach(Array(openTasks.enumerated()), id: \.element.id) { index, task in
                    mindObject(for: task)
                        .position(model.isTransforming ? center(in: geometry.size) : taskPosition(index: index, size: geometry.size))
                        .rotationEffect(.degrees(model.isTransforming ? Double(index * 22) : 0))
                        .scaleEffect(model.isTransforming ? 0.42 : 1)
                        .opacity(model.isTransforming ? 0.15 : 1)
                        .animation(objectAnimation(index: index), value: model.isTransforming)
                }

                ForEach(Array(model.projects.prefix(5).enumerated()), id: \.element.id) { index, project in
                    ProjectOrb(project: project, taskCount: model.tasks.filter { $0.projectID == project.id && $0.status != .completed && $0.status != .trashed }.count)
                        .onTapGesture {
                            model.selectedSection = .projects
                            transformToStructured()
                        }
                        .position(model.isTransforming ? center(in: geometry.size) : projectPosition(index: index, size: geometry.size))
                        .rotation3DEffect(.degrees(model.isTransforming ? 70 : -8), axis: (x: 0.7, y: 1, z: 0.2))
                        .scaleEffect(model.isTransforming ? 0.35 : 1)
                        .opacity(model.isTransforming ? 0.12 : 1)
                        .animation(objectAnimation(index: index + 4), value: model.isTransforming)
                }

                VStack(spacing: 14) {
                    Button(action: transformToStructured) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 0.92, green: 0.48, blue: 0.24).opacity(0.94),
                                            Color(red: 0.58, green: 0.19, blue: 0.08).opacity(0.88),
                                        ],
                                        center: .topLeading,
                                        startRadius: 4,
                                        endRadius: 92
                                    )
                                )
                                .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                                .shadow(color: Color.orange.opacity(0.22), radius: 34)
                            Text("MAKE IT\nMAKE SENSE")
                                .multilineTextAlignment(.center)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(.white)
                        }
                        .frame(width: 142, height: 142)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("makeItMakeSenseButton")

                    Button {
                        model.isPresentingNewTask = true
                    } label: {
                        Label("Capture a thought", systemImage: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .glassPanel(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 30)
                .scaleEffect(model.isTransforming ? 0.74 : 1)
                .opacity(model.isTransforming ? 0 : 1)

                if openTasks.isEmpty && model.projects.isEmpty {
                    EmptyMindSpaceCard {
                        model.isPresentingNewTask = true
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height - 94)
                }
            }
        }
        .padding(24)
        .accessibilityIdentifier("mindSpaceRoot")
    }

    @ViewBuilder
    private func mindObject(for task: MindSpaceTask) -> some View {
        if task.category?.localizedCaseInsensitiveContains("idea") == true {
            IdeaSphere(task: task, projectName: model.project(for: task)?.name)
                .onTapGesture { model.selectedTask = task }
        } else {
            FloatingTaskCard(task: task, projectName: model.project(for: task)?.name)
                .onTapGesture { model.selectedTask = task }
        }
    }

    private func orbitalGuides(in size: CGSize) -> some View {
        ZStack {
            Ellipse()
                .stroke(.white.opacity(model.isTransforming ? 0.13 : 0.045), lineWidth: 1)
                .frame(width: min(size.width * 0.72, 820), height: min(size.height * 0.58, 460))
                .rotationEffect(.degrees(-9))
            Ellipse()
                .stroke(Color.blue.opacity(model.isTransforming ? 0.15 : 0.035), lineWidth: 1)
                .frame(width: min(size.width * 0.48, 580), height: min(size.height * 0.78, 600))
                .rotationEffect(.degrees(24))
        }
    }

    private func transformToStructured() {
        guard !model.isTransforming else { return }
        if model.preferences.reducedMotion {
            model.makeSense()
            return
        }
        model.isTransforming = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(860))
            model.makeSense()
            model.isTransforming = false
        }
    }

    private func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2 + 20)
    }

    private func taskPosition(index: Int, size: CGSize) -> CGPoint {
        let positions: [(CGFloat, CGFloat)] = [
            (0.16, 0.24), (0.78, 0.22), (0.12, 0.55), (0.84, 0.54), (0.26, 0.78),
            (0.68, 0.80), (0.35, 0.34), (0.67, 0.38), (0.42, 0.88), (0.91, 0.74),
        ]
        let point = positions[index % positions.count]
        return CGPoint(x: size.width * point.0, y: size.height * point.1)
    }

    private func projectPosition(index: Int, size: CGSize) -> CGPoint {
        let positions: [(CGFloat, CGFloat)] = [(0.27, 0.48), (0.73, 0.67), (0.52, 0.22), (0.09, 0.82), (0.90, 0.34)]
        let point = positions[index % positions.count]
        return CGPoint(x: size.width * point.0, y: size.height * point.1)
    }

    private func objectAnimation(index: Int) -> Animation {
        .easeInOut(duration: 0.72).delay(Double(index) * 0.025)
    }
}

private struct FloatingTaskCard: View {
    let task: MindSpaceTask
    let projectName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(projectName ?? "Inbox")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                if task.isToday { Image(systemName: "sun.max.fill").font(.caption2).foregroundStyle(.orange.opacity(0.8)) }
            }
            Text(task.title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
            if let notes = task.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(.white.opacity(0.48)).lineLimit(2)
            }
        }
        .padding(14)
        .frame(width: 194, alignment: .leading)
        .glassPanel(cornerRadius: 17)
        .accessibilityLabel(task.title)
    }

    private var accent: Color {
        switch task.energy?.lowercased() {
        case "high": .orange
        case "low": .purple
        default: .blue
        }
    }
}

private struct IdeaSphere: View {
    let task: MindSpaceTask
    let projectName: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.purple.opacity(0.55), .indigo.opacity(0.18)], center: .topLeading, startRadius: 4, endRadius: 72))
                .overlay(Circle().stroke(.white.opacity(0.13), lineWidth: 1))
                .shadow(color: .purple.opacity(0.18), radius: 20)
            VStack(spacing: 5) {
                Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.55))
                Text(task.title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(2)
            }
            .padding(13)
        }
        .frame(width: 112, height: 112)
        .accessibilityLabel("Idea: \(task.title)")
    }
}

private struct ProjectOrb: View {
    let project: MindSpaceProject
    let taskCount: Int

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 27, weight: .light))
            Text(project.name).font(.caption.weight(.semibold)).lineLimit(1)
            Text("\(taskCount) open").font(.caption2).opacity(0.48)
        }
        .foregroundStyle(.white.opacity(0.84))
        .frame(width: 108, height: 92)
        .glassPanel(cornerRadius: 15)
        .accessibilityLabel("Project \(project.name), \(taskCount) open tasks")
    }
}

private struct EmptyMindSpaceCard: View {
    let capture: () -> Void

    var body: some View {
        Button(action: capture) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                VStack(alignment: .leading, spacing: 2) {
                    Text("This space is quiet.").font(.subheadline.weight(.medium))
                    Text("Capture a thought and it will appear here.").font(.caption).opacity(0.55)
                }
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(15)
            .glassPanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}
