import AppKit
import SwiftUI
import Combine

/// Observable state that drives the overlay UI. Either transcriber populates this.
@MainActor
class OverlayState: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    private var cancellables = Set<AnyCancellable>()

    /// Fix #9: Use sink + store(in:) instead of assign(to: &$prop) so that
    /// cancellables.removeAll() actually cancels subscriptions from the previous transcriber.
    /// assign(to: &$property) ties lifetime to the Published property and ignores cancellables.

    /// Binds to a SpeechTranscriber's published properties.
    func bind(to transcriber: SpeechTranscriber) {
        cancellables.removeAll()
        transcriber.$isRecording.sink { [weak self] in self?.isRecording = $0 }.store(in: &cancellables)
        transcriber.$audioLevel.sink { [weak self] in self?.audioLevel = $0 }.store(in: &cancellables)
        transcriber.$transcribedText.sink { [weak self] in self?.transcribedText = $0 }.store(in: &cancellables)
        transcriber.$isEnhancing.sink { [weak self] in self?.isEnhancing = $0 }.store(in: &cancellables)
    }

    /// Binds to a WhisperTranscriber's published properties.
    func bind(to transcriber: WhisperTranscriber) {
        cancellables.removeAll()
        transcriber.$isRecording.sink { [weak self] in self?.isRecording = $0 }.store(in: &cancellables)
        transcriber.$audioLevel.sink { [weak self] in self?.audioLevel = $0 }.store(in: &cancellables)
        transcriber.$transcribedText.sink { [weak self] in self?.transcribedText = $0 }.store(in: &cancellables)
        transcriber.$isEnhancing.sink { [weak self] in self?.isEnhancing = $0 }.store(in: &cancellables)
    }

    /// Binds to a FluidAudioTranscriber's published properties.
    func bind(to transcriber: FluidAudioTranscriber) {
        cancellables.removeAll()
        transcriber.$isRecording.sink { [weak self] in self?.isRecording = $0 }.store(in: &cancellables)
        transcriber.$audioLevel.sink { [weak self] in self?.audioLevel = $0 }.store(in: &cancellables)
        transcriber.$transcribedText.sink { [weak self] in self?.transcribedText = $0 }.store(in: &cancellables)
        transcriber.$isEnhancing.sink { [weak self] in self?.isEnhancing = $0 }.store(in: &cancellables)
    }

    func reset() {
        isRecording = false
        audioLevel = 0
        transcribedText = ""
        isEnhancing = false
        cancellables.removeAll()
    }
}

/// A borderless, non-activating floating panel that sits at the bottom-center
/// (or top-center in notch mode) of the main screen and hosts the WaveformView.
class RecordingOverlayWindow: NSPanel {

    private var hostingView: NSHostingView<OverlayContent>?
    private(set) var isNotchMode = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
    }

    func show(state: OverlayState, notchMode: Bool = false) {
        self.isNotchMode = notchMode

        let content = OverlayContent(state: state, notchMode: notchMode)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
        hostingView = hosting

        if notchMode {
            // Notch mode: position at top-center, flush with top of screen
            // Use a higher window level so it sits above everything like the real notch
            level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

            let shadowPadding: CGFloat = 20
            let contentWidth: CGFloat = 360
            let contentHeight: CGFloat = 140
            let totalWidth = contentWidth + shadowPadding * 2
            let totalHeight = contentHeight + shadowPadding

            if let screen = NSScreen.main {
                let x = screen.frame.origin.x + (screen.frame.width - totalWidth) / 2
                let y = screen.frame.origin.y + screen.frame.height - totalHeight
                setFrame(CGRect(x: x, y: y, width: totalWidth, height: totalHeight), display: false)
            }
        } else {
            // Default pill mode: position at bottom-center
            level = .floating
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let size = CGSize(width: 360, height: 140)
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.midX - size.width / 2
                let y = screen.visibleFrame.minY + 30
                setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: false)
            }
        }

        alphaValue = 1
        orderFront(nil)
    }

    func hide(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}

// MARK: - SwiftUI content hosted inside the panel

private struct OverlayContent: View {
    @ObservedObject var state: OverlayState
    var notchMode: Bool = false

    var body: some View {
        WaveformView(
            audioLevel: state.audioLevel,
            isRecording: state.isRecording,
            transcribedText: state.transcribedText,
            isEnhancing: state.isEnhancing,
            notchMode: notchMode
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, notchMode ? 0 : 8)
    }
}
