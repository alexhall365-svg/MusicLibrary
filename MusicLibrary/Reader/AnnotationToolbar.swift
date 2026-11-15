import SwiftUI

/// The floating vertical toolbar shown while annotating.
struct AnnotationToolbar: View {
    @Bindable var controller: AnnotationController
    let onDone: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(AnnotationTool.allCases) { tool in
                    toolButton(tool)
                }

                divider

                ForEach(colors) { ink in
                    Button {
                        if controller.tool == .highlighter {
                            controller.highlighterColor = ink
                        } else {
                            controller.penColor = ink
                            controller.tool = .pen
                        }
                    } label: {
                        Circle()
                            .fill(ink.color)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                            .padding(4)
                            .overlay(
                                Circle().stroke(Color.accentColor, lineWidth: isSelected(ink) ? 2.5 : 0)
                            )
                    }
                    .accessibilityLabel(ink.label)
                    .accessibilityAddTraits(isSelected(ink) ? .isSelected : [])
                }

                divider

                iconButton("arrow.uturn.backward", label: "Undo") { controller.undo() }
                iconButton("arrow.uturn.forward", label: "Redo") { controller.redo() }
                iconButton(
                    controller.fingerDrawing ? "hand.draw.fill" : "hand.draw",
                    label: controller.fingerDrawing ? "Finger drawing on" : "Finger drawing off",
                    highlighted: controller.fingerDrawing
                ) {
                    controller.fingerDrawing.toggle()
                }

                divider

                Button(action: onDone) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Done annotating")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    private var colors: [InkColor] {
        controller.tool == .highlighter ? InkColor.highlighterColors : InkColor.penColors
    }

    private func isSelected(_ ink: InkColor) -> Bool {
        switch controller.tool {
        case .pen: return controller.penColor == ink
        case .highlighter: return controller.highlighterColor == ink
        case .eraser: return false
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 28, height: 1)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        iconButton(tool.systemImage, label: tool.label, highlighted: controller.tool == tool) {
            controller.tool = tool
        }
    }

    private func iconButton(
        _ systemImage: String,
        label: String,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(highlighted ? Color.accentColor.opacity(0.3) : Color.clear, in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}
