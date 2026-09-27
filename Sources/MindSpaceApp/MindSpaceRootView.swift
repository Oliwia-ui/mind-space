import SwiftUI

struct MindSpaceRootView: View {
    @ObservedObject var model: MindSpaceAppModel

    var body: some View {
        ZStack {
            CosmicBackground()
            if model.mode == .mindSpace {
                MindSpaceCanvasView(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                StructuredTaskView(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if let task = model.undoableTask {
                UndoBanner(title: task.title, undo: model.undoTaskCreation, dismiss: model.dismissUndo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.undoableTask?.id)
        .animation(
            model.preferences.reducedMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.9),
            value: model.mode
        )
        .sheet(isPresented: $model.isPresentingNewTask) {
            TaskEditorView(model: model, task: nil)
        }
        .sheet(item: $model.selectedTask) { task in
            TaskEditorView(model: model, task: task)
        }
        .sheet(isPresented: $model.isNamingGalaxy, onDismiss: model.cancelGalaxyCreation) {
            NewGalaxyView(model: model)
        }
        .sheet(item: $model.editingProject) { project in
            ProjectGalaxyEditorView(model: model, project: project)
        }
        .alert("Mind Space needs attention", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct UndoBanner: View {
    let title: String
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Text("Saved “\(title)”")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                Button("Undo", action: undo)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange.opacity(0.9))
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss undo")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassPanel(cornerRadius: 14)
            .padding(.bottom, 26)
        }
        .allowsHitTesting(true)
    }
}

struct CosmicBackground: View {
    private let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.08, 0.12, 2, 0.38), (0.18, 0.72, 1, 0.35), (0.29, 0.22, 1.5, 0.28),
        (0.42, 0.82, 2, 0.25), (0.55, 0.14, 1, 0.42), (0.67, 0.64, 1.5, 0.34),
        (0.78, 0.28, 2, 0.30), (0.91, 0.76, 1, 0.45), (0.86, 0.08, 1.5, 0.25),
        (0.12, 0.43, 1, 0.30), (0.35, 0.53, 1, 0.22), (0.72, 0.91, 2, 0.20),
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.025, green: 0.035, blue: 0.065),
                        Color(red: 0.01, green: 0.014, blue: 0.026),
                        .black,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [Color.indigo.opacity(0.10), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 620
                )

                if let backdrop = NSImage(named: "mind-space-backdrop")
                    ?? Bundle.module.image(forResource: "mind-space-backdrop") {
                    Image(nsImage: backdrop)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(0.55)
                        .overlay(Color.black.opacity(0.34))
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }

                ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(.white.opacity(star.3))
                        .frame(width: star.2, height: star.2)
                        .position(x: geometry.size.width * star.0, y: geometry.size.height * star.1)
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 18) -> some View {
        background(.ultraThinMaterial.opacity(0.62), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
    }
}
