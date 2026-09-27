import MindSpaceCore
import SwiftUI

struct MindSpaceCanvasView: View {
    @ObservedObject var model: MindSpaceAppModel
    @ObservedObject private var physics: MindSpacePhysicsController
    private let driftField = ThoughtDriftField()

    init(model: MindSpaceAppModel) {
        self.model = model
        _physics = ObservedObject(wrappedValue: model.physics)
    }

    private var openTasks: [MindSpaceTask] {
        model.tasks.filter { $0.status != .completed && $0.status != .trashed }
    }

    private var visibleProjects: [MindSpaceProject] {
        model.projects
    }

    private var layoutSignature: [String] {
        openTasks.map { "task:\($0.id):\($0.category ?? ""):\($0.projectID ?? "")" }
            + visibleProjects.map { "project:\($0.id)" }
    }

    var body: some View {
        canvas()
            .onAppear { model.startDrifting() }
    }

    private func canvas() -> some View {
        GeometryReader { geometry in
            let defaults = defaultBodies(in: geometry.size)
            let kinds = objectKinds
            let bounds = safeBounds(in: geometry.size)

            ZStack {
                orbitalGuides(in: geometry.size)
                galaxyConnections(in: geometry.size)

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

                Button {
                    physics.reset(defaultBodies: defaults, kinds: kinds, bounds: bounds)
                } label: {
                    Label("Reset Layout", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassPanel(cornerRadius: 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.58))
                .position(x: geometry.size.width - 78, y: 48)
                .accessibilityIdentifier("resetMindSpaceLayoutButton")

                ForEach(Array(openTasks.enumerated()), id: \.element.id) { index, task in
                    let fallback = taskPosition(index: index, size: geometry.size)
                    let center = physics.center(for: task.id, fallback: thoughtPoint(fallback))
                    mindObject(for: task)
                        .scaleEffect(objectScale(for: task.id))
                        .shadow(
                            color: objectGlow(for: task.id),
                            radius: isGroupingHighlighted(task.id) ? 28 : (physics.contactIDs.contains(task.id) ? 19 : 0)
                        )
                        .position(model.isTransforming ? centerPoint(in: geometry.size) : point(center))
                        .offset(driftOffset(for: task.id))
                        .animation(driftAnimation(for: task.id), value: model.isDrifting)
                        .rotationEffect(.degrees(model.isTransforming ? Double(index * 22) : 0))
                        .scaleEffect(model.isTransforming ? 0.42 : 1)
                        .opacity(model.isTransforming ? 0.15 : 1)
                        .animation(objectAnimation(index: index), value: model.isTransforming)
                        .animation(physics.draggedObjectID == task.id ? nil : .easeOut(duration: 0.09), value: center)
                        .animation(.easeOut(duration: 0.24), value: physics.contactIDs.contains(task.id))
                        .gesture(dragGesture(for: task.id, fallback: center))
                        .onTapGesture { model.selectedTask = task }
                }

                ForEach(Array(visibleProjects.enumerated()), id: \.element.id) { index, project in
                    let fallback = projectPosition(index: index, size: geometry.size)
                    let center = physics.center(for: project.id, fallback: thoughtPoint(fallback))
                    ProjectOrb(
                        project: project,
                        taskCount: model.tasks.filter {
                            $0.projectID == project.id && $0.status != .completed && $0.status != .trashed
                        }.count
                    )
                    .scaleEffect(objectScale(for: project.id))
                    .shadow(
                        color: objectGlow(for: project.id),
                        radius: isGroupingHighlighted(project.id) ? 28 : (physics.contactIDs.contains(project.id) ? 19 : 0)
                    )
                    .position(model.isTransforming ? centerPoint(in: geometry.size) : point(center))
                    .offset(driftOffset(for: project.id))
                    .animation(driftAnimation(for: project.id), value: model.isDrifting)
                    .rotation3DEffect(.degrees(model.isTransforming ? 70 : -8), axis: (x: 0.7, y: 1, z: 0.2))
                    .scaleEffect(model.isTransforming ? 0.35 : 1)
                    .opacity(model.isTransforming ? 0.12 : 1)
                    .animation(objectAnimation(index: index + 4), value: model.isTransforming)
                    .animation(physics.draggedObjectID == project.id ? nil : .easeOut(duration: 0.09), value: center)
                    .animation(.easeOut(duration: 0.24), value: physics.contactIDs.contains(project.id))
                    .gesture(dragGesture(for: project.id, fallback: center))
                    .onTapGesture {
                        model.selectedProjectID = project.id
                        model.selectedSection = .projects
                        transformToStructured()
                    }
                }

                if let preview = physics.groupingPreview,
                   let first = physics.bodies.first(where: { $0.id == preview.draggedID }),
                   let second = physics.bodies.first(where: { $0.id == preview.targetID }) {
                    GroupingPreviewBadge(preview: preview)
                        .position(
                            x: (first.center.x + second.center.x) / 2,
                            y: (first.center.y + second.center.y) / 2 - 46
                        )
                        .allowsHitTesting(false)
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

                if openTasks.isEmpty && visibleProjects.isEmpty {
                    EmptyMindSpaceCard {
                        model.isPresentingNewTask = true
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height - 94)
                }
            }
            .coordinateSpace(name: "mindSpaceCanvas")
            .onAppear {
                physics.configure(defaultBodies: defaults, kinds: kinds, bounds: bounds)
            }
            .onChange(of: geometry.size) { _, _ in
                physics.configure(defaultBodies: defaults, kinds: kinds, bounds: bounds)
            }
            .onChange(of: layoutSignature) { _, _ in
                physics.configure(defaultBodies: defaults, kinds: kinds, bounds: bounds)
            }
            .alert("Mind Space layout needs attention", isPresented: physicsErrorBinding) {
                Button("OK", role: .cancel) { physics.errorMessage = nil }
            } message: {
                Text(physics.errorMessage ?? "Unknown layout error")
            }
        }
        .padding(24)
        .accessibilityIdentifier("mindSpaceRoot")
    }

    @ViewBuilder
    private func mindObject(for task: MindSpaceTask) -> some View {
        if task.category?.localizedCaseInsensitiveContains("idea") == true {
            IdeaSphere(task: task, projectName: model.project(for: task)?.name)
        } else {
            FloatingTaskCard(task: task, projectName: model.project(for: task)?.name)
        }
    }

    private var objectKinds: [String: MindSpaceObjectKind] {
        var kinds = Dictionary(uniqueKeysWithValues: openTasks.map { ($0.id, MindSpaceObjectKind.task) })
        for project in visibleProjects { kinds[project.id] = .project }
        return kinds
    }

    private func defaultBodies(in size: CGSize) -> [ThoughtBody] {
        let tasks = openTasks.enumerated().map { index, task in
            let position = taskPosition(index: index, size: size)
            let radius = task.category?.localizedCaseInsensitiveContains("idea") == true ? 58.0 : 104.0
            return ThoughtBody(id: task.id, center: thoughtPoint(position), radius: radius)
        }
        let projects = visibleProjects.enumerated().map { index, project in
            ThoughtBody(id: project.id, center: thoughtPoint(projectPosition(index: index, size: size)), radius: 61)
        }
        return tasks + projects
    }

    private func dragGesture(for objectID: String, fallback: ThoughtPoint) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("mindSpaceCanvas"))
            .onChanged { value in
                if physics.draggedObjectID != objectID {
                    physics.beginDragging(objectID: objectID, at: fallback)
                }
                physics.drag(objectID: objectID, to: thoughtPoint(value.location))
            }
            .onEnded { value in
                physics.drag(objectID: objectID, to: thoughtPoint(value.location))
                if let pair = physics.endDragging(objectID: objectID) {
                    model.handleGroup(pair)
                }
            }
    }

    private func galaxyConnections(in size: CGSize) -> some View {
        Canvas { context, _ in
            let centers = Dictionary(
                uniqueKeysWithValues: physics.bodies.map {
                    ($0.id, CGPoint(x: $0.center.x, y: $0.center.y))
                }
            )

            for project in visibleProjects {
                guard let projectCenter = centers[project.id] else { continue }
                let members = openTasks.filter { $0.projectID == project.id }
                let color = projectColor(project.colorToken)

                if !members.isEmpty {
                    let orbitRadius = min(86 + CGFloat(members.count) * 10, 168)
                    let orbit = Path(ellipseIn: CGRect(
                        x: projectCenter.x - orbitRadius,
                        y: projectCenter.y - orbitRadius * 0.62,
                        width: orbitRadius * 2,
                        height: orbitRadius * 1.24
                    ))
                    context.stroke(
                        orbit,
                        with: .color(color.opacity(0.10)),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 8])
                    )
                }

                for task in members {
                    guard let taskCenter = centers[task.id] else { continue }
                    var line = Path()
                    line.move(to: projectCenter)
                    line.addLine(to: taskCenter)
                    context.stroke(line, with: .color(color.opacity(0.25)), lineWidth: 0.85)
                }
            }

            if let preview = physics.groupingPreview,
               let first = centers[preview.draggedID],
               let second = centers[preview.targetID] {
                var line = Path()
                line.move(to: first)
                line.addLine(to: second)
                context.stroke(
                    line,
                    with: .color(Color.orange.opacity(preview.isReady ? 0.82 : 0.48)),
                    style: StrokeStyle(lineWidth: preview.isReady ? 2 : 1.25, dash: [5, 5])
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func isGroupingHighlighted(_ objectID: String) -> Bool {
        guard let preview = physics.groupingPreview else { return false }
        return preview.draggedID == objectID || preview.targetID == objectID
    }

    private func objectScale(for objectID: String) -> CGFloat {
        if let preview = physics.groupingPreview,
           preview.draggedID == objectID || preview.targetID == objectID {
            return preview.isReady ? 1.065 : 1.035
        }
        return physics.contactIDs.contains(objectID) ? 1.025 : 1
    }

    private func objectGlow(for objectID: String) -> Color {
        if isGroupingHighlighted(objectID) { return .orange.opacity(0.42) }
        return physics.contactIDs.contains(objectID) ? .cyan.opacity(0.30) : .clear
    }

    private func projectColor(_ token: String) -> Color {
        switch token.lowercased() {
        case "orange": .orange
        case "purple": .purple
        case "green": .green
        default: .blue
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

    private func safeBounds(in size: CGSize) -> ThoughtBounds {
        ThoughtBounds(minX: 14, minY: 128, maxX: Double(size.width) - 14, maxY: Double(size.height) - 18)
    }

    private func centerPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2 + 20)
    }

    private func taskPosition(index: Int, size: CGSize) -> CGPoint {
        automaticPosition(index: index, total: openTasks.count + visibleProjects.count, size: size)
    }

    private func projectPosition(index: Int, size: CGSize) -> CGPoint {
        automaticPosition(
            index: openTasks.count + index,
            total: openTasks.count + visibleProjects.count,
            size: size
        )
    }

    private func automaticPosition(index: Int, total: Int, size: CGSize) -> CGPoint {
        let progress = sqrt(Double(index + 1) / Double(max(total, 1)))
        let angle = Double(index) * 2.399_963
        let radialScale = 0.19 + 0.29 * progress
        return CGPoint(
            x: size.width / 2 + cos(angle) * size.width * radialScale,
            y: size.height / 2 + sin(angle) * size.height * radialScale * 0.72 + 32
        )
    }

    private func objectAnimation(index: Int) -> Animation {
        .easeInOut(duration: 0.72).delay(Double(index) * 0.025)
    }

    private func thoughtPoint(_ point: CGPoint) -> ThoughtPoint {
        ThoughtPoint(x: Double(point.x), y: Double(point.y))
    }

    private func point(_ point: ThoughtPoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }

    /// Calm ambient hovering, handed to the render server as a repeating animation so an
    /// idle Mind Space costs no per-frame view evaluation. The saved position never changes.
    private func driftOffset(for id: String) -> CGSize {
        guard model.isDrifting, !model.preferences.reducedMotion, physics.draggedObjectID != id else {
            return .zero
        }
        let offset = driftField.hoverTarget(forID: id)
        return CGSize(width: offset.x, height: offset.y)
    }

    private func driftAnimation(for id: String) -> Animation {
        .easeInOut(duration: driftField.hoverDuration(forID: id))
        .repeatForever(autoreverses: true)
    }

    private var physicsErrorBinding: Binding<Bool> {
        Binding(
            get: { physics.errorMessage != nil },
            set: { if !$0 { physics.errorMessage = nil } }
        )
    }
}

private struct GroupingPreviewBadge: View {
    let preview: ThoughtGroupPreview

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(preview.progress, 0.06))
                    .stroke(
                        preview.isReady ? Color.orange : Color.white.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)

            Text(preview.isReady ? "Release to form constellation" : "Hold to connect")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.black.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(Color.orange.opacity(preview.isReady ? 0.58 : 0.22), lineWidth: 1))
        .shadow(color: .orange.opacity(preview.isReady ? 0.24 : 0.08), radius: 16)
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
        .foregroundStyle(projectColor)
        .frame(width: 108, height: 92)
        .glassPanel(cornerRadius: 15)
        .shadow(color: projectColor.opacity(0.14), radius: 18)
        .accessibilityLabel("Project \(project.name), \(taskCount) open tasks")
    }

    private var projectColor: Color {
        switch project.colorToken.lowercased() {
        case "orange": .orange.opacity(0.88)
        case "purple": .purple.opacity(0.88)
        case "green": .green.opacity(0.82)
        default: .blue.opacity(0.88)
        }
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
