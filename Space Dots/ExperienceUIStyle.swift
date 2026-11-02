import SwiftUI
import simd

enum ExperienceUIStyle {
    static let primaryRed = Color(red: 177.0 / 255.0, green: 38.0 / 255.0, blue: 61.0 / 255.0)
    static let primaryRedHighlighted = Color(red: 255.0 / 255.0, green: 110.0 / 255.0, blue: 135.0 / 255.0)
    static let primaryText = Color(red: 255.0 / 255.0, green: 240.0 / 255.0, blue: 240.0 / 255.0)
    static let primaryButtonMinimumWidth: CGFloat = 235
    static let primaryButtonHeight: CGFloat = 58
    static let primaryButtonFontSize: CGFloat = 24
    static let panelCornerRadius: CGFloat = 28
    static let theMomentPlayButtonTitle = "It's time go!"
    // Keep native RealityKit companions on the same spatial plane as the
    // portal's baked-in logo and Home artwork.
    static let portalContentDepthOffset: CGFloat = -250
}

struct SpaceDotsTitleTreatment: View {
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: -2) {
            Text("PROJECT")
                .font(.system(size: 22, weight: .medium, design: .default))
                .tracking(8)
                .foregroundStyle(ExperienceUIStyle.primaryRed)

            Text("SPACE DOTS")
                .font(.system(size: 78, weight: .semibold, design: .default))
                .tracking(7)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A button that plays the system's tap feedback, which visionOS renders
/// as its standard interface sound.
struct FeedbackButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var tapCount = 0

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            label()
        }
        .sensoryFeedback(.selection, trigger: tapCount)
    }
}

struct ExperienceGlassBackButton: View {
    var movesPanel = false
    let action: () -> Void

    var body: some View {
        PanelButton(shape: Capsule(), movesPanel: movesPanel, action: action) {
            Text("Close")
                .font(.system(size: 16, weight: .medium, design: .default))
                .foregroundStyle(ExperienceUIStyle.primaryText)
                .frame(minWidth: 89, minHeight: 44)
                .padding(.horizontal, 10)
                .glassBackgroundEffect(in: Capsule())
        }
        .accessibilityLabel("Close")
    }
}

/// A plain button whose system gaze highlight and hit area follow `shape`,
/// so the highlight sits exactly on the visible control.
///
/// With `movesPanel` it is a control on the immersive screen: a short pinch
/// still triggers `action`, while holding or dragging it moves the screen
/// and a two-handed pinch resizes it. It stays a real `Button` there too,
/// because only a button plays the system's tap sound on visionOS.
struct PanelButton<S: Shape, Label: View>: View {
    let shape: S
    var movesPanel = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    /// Whether the pinch on this button went on to move or resize the screen.
    @State private var pressMovedPanel = false

    var body: some View {
        if movesPanel {
            Button {
                guard !pressMovedPanel else { return }
                action()
            } label: {
                label()
                    .contentShape(.interaction, shape)
                    .contentShape(.hoverEffect, shape)
                    .hoverEffect(.highlight)
            }
            .buttonStyle(.plain)
            .panelHandle(alongsideButton: $pressMovedPanel)
        } else {
            FeedbackButton(action: action) {
                label()
                    .contentShape(.interaction, shape)
                    .contentShape(.hoverEffect, shape)
                    .hoverEffect(.highlight)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Lets a view on the immersive screen move and resize that screen, using
/// the same rule as the screen's grab surfaces: a pinch counts as a tap
/// only when it is short and stays in place.
private struct PanelHandleModifier: ViewModifier {
    let onTap: (() -> Void)?
    /// Set on a `Button`, which keeps its own tap: the gestures then run
    /// alongside it and report here whether the pinch became a handle.
    var buttonPressMovedPanel: Binding<Bool>?

    @Environment(AppModel.self) private var appModel
    @Environment(\.panelHandleActivity) private var reportActivity
    @GestureState private var dragIsDown = false
    @GestureState private var magnifyIsDown = false
    @State private var pressStart: Date?
    @State private var pressBecameHandle = false
    @State private var handleIsActive = false
    /// Hand travel at the moment the move began, so it starts without a jump.
    @State private var translationOrigin = SIMD3<Float>.zero
    @State private var translation = SIMD3<Float>.zero
    /// Resizes finished earlier in this grab, and the one in progress.
    @State private var committedMagnification: Float = 1
    @State private var magnification: Float = 1
    @State private var tapCount = 0

    private static let tapMaximumDuration: TimeInterval = 0.35
    private static let tapMaximumTravel: Float = 0.025
    // SwiftUI measures the immersive space in points, 1,360 to the metre.
    private static let pointsPerMetre: Float = 1_360

    func body(content: Content) -> some View {
        Group {
            if buttonPressMovedPanel != nil {
                content.simultaneousGesture(drag.simultaneously(with: magnify))
            } else {
                content.gesture(drag.simultaneously(with: magnify))
            }
        }
        .onChange(of: dragIsDown || magnifyIsDown) { _, isDown in
            guard !isDown else { return }
            endHandle()
            // A cancelled pinch never reaches `onEnded`; forget it once
            // that had its chance to read the press.
            Task { @MainActor in
                await Task.yield()
                if !dragIsDown { pressStart = nil }
            }
        }
        .sensoryFeedback(.selection, trigger: tapCount)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .immersiveSpace)
            .updating($dragIsDown) { _, isDown, _ in isDown = true }
            .onChanged { value in
                if pressStart == nil {
                    pressStart = Date()
                    pressBecameHandle = false
                    buttonPressMovedPanel?.wrappedValue = false
                }
                // SwiftUI's vertical axis points down, RealityKit's up.
                let travel = SIMD3<Float>(
                    Float(value.translation3D.x),
                    Float(-value.translation3D.y),
                    Float(value.translation3D.z)
                ) / Self.pointsPerMetre
                let held = Date().timeIntervalSince(pressStart ?? Date())
                if !handleIsActive,
                   simd_length(travel) > Self.tapMaximumTravel
                    || held >= Self.tapMaximumDuration {
                    translationOrigin = travel
                    beginHandle()
                }
                guard handleIsActive else { return }
                translation = travel - translationOrigin
                sendUpdate()
            }
            .onEnded { value in
                let travel = Float(value.translation3D.length) / Self.pointsPerMetre
                let held = Date().timeIntervalSince(pressStart ?? .distantPast)
                let wasTap = !pressBecameHandle
                    && travel <= Self.tapMaximumTravel
                    && held < Self.tapMaximumDuration
                pressStart = nil
                if wasTap, let onTap {
                    tapCount += 1
                    onTap()
                }
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($magnifyIsDown) { _, isDown, _ in isDown = true }
            .onChanged { value in
                beginHandle()
                magnification = Float(value.magnification)
                sendUpdate()
            }
            .onEnded { _ in
                committedMagnification *= magnification
                magnification = 1
            }
    }

    private func beginHandle() {
        guard !handleIsActive else { return }
        handleIsActive = true
        pressBecameHandle = true
        buttonPressMovedPanel?.wrappedValue = true
        translation = .zero
        committedMagnification = 1
        magnification = 1
        reportActivity(true)
        appModel.panelHandle.begin()
    }

    private func sendUpdate() {
        appModel.panelHandle.update(
            translation,
            committedMagnification * magnification
        )
    }

    private func endHandle() {
        guard handleIsActive else { return }
        handleIsActive = false
        appModel.panelHandle.end()
        reportActivity(false)
    }
}

private struct PanelHandleActivityKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Called when a control starts and stops moving or resizing the
    /// immersive screen, so its host can keep the controls on screen.
    var panelHandleActivity: (Bool) -> Void {
        get { self[PanelHandleActivityKey.self] }
        set { self[PanelHandleActivityKey.self] = newValue }
    }
}

private struct ExperienceRedButtonHoverModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .hoverEffect(.highlight)
            .hoverEffect { effect, isActive, _ in
                effect.animation(.easeInOut(duration: 0.16)) {
                $0.scaleEffect(isActive ? 1.05 : 1.0)
                }
            }
    }
}

extension View {
    /// Flattens the subtree only when `isEnabled`. The immersive panel keeps
    /// its controls unflattened so their system gaze highlights render on
    /// the controls themselves.
    @ViewBuilder
    func compositingGroup(isEnabled: Bool) -> some View {
        if isEnabled {
            compositingGroup()
        } else {
            self
        }
    }

    func panelHandle(onTap: (() -> Void)? = nil) -> some View {
        modifier(PanelHandleModifier(onTap: onTap))
    }

    /// The same handle on a `Button`, whose own tap keeps triggering its
    /// action; `pressMovedPanel` tells it when to ignore that tap.
    func panelHandle(alongsideButton pressMovedPanel: Binding<Bool>) -> some View {
        modifier(PanelHandleModifier(
            onTap: nil,
            buttonPressMovedPanel: pressMovedPanel
        ))
    }

    func experienceRedButtonHover() -> some View {
        modifier(ExperienceRedButtonHoverModifier())
    }

}
