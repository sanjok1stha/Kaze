import SwiftUI

struct WaveformView: View {
    var audioLevel: Float
    var isRecording: Bool
    var transcribedText: String
    var isEnhancing: Bool = false
    var notchMode: Bool = false

    // Number of bars in the waveform
    private let barCount = 16
    @State private var phases: [Double] = (0..<16).map { Double($0) * 0.4 }
    @State private var animTimer: Timer?
    @State private var appeared = false
    @State private var textScrollID = UUID()
    @State private var spinAngle: Double = 0

    /// Whether we have text to show (drives expansion)
    private var hasText: Bool { !transcribedText.isEmpty && !isEnhancing }

    /// Compact when enhancing or no text; expanded when recording with text
    private var isCompact: Bool { isEnhancing || !hasText }

    private var cornerRadius: CGFloat { isCompact ? 24 : 20 }
    private var textOverflows: Bool { transcribedText.count > 38 }

    // Notch mode corner radii (same as teleprompter)
    private var notchTopCornerRadius: CGFloat { isCompact ? 6 : 14 }
    private var notchBottomCornerRadius: CGFloat { isCompact ? 10 : 20 }

    var body: some View {
        Group {
            if notchMode {
                notchBody
            } else {
                pillBody
            }
        }
        .onAppear {
            startAnimating()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                appeared = true
            }
        }
        .onDisappear {
            stopAnimating()
            appeared = false
        }
    }

    // MARK: - Pill mode body (bottom-center floating pill)

    private var pillBody: some View {
        VStack(spacing: isCompact ? 0 : 8) {
            HStack(spacing: 10) {
                if isEnhancing {
                    processingSpinner
                } else {
                    kazeIcon
                }

                if isEnhancing {
                    processingBars
                        .transition(.opacity)
                } else {
                    waveformBars
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isEnhancing)

            if hasText {
                transcriptionTextRow(maxWidth: 260)
            }
        }
        .padding(.horizontal, isCompact ? 14 : 20)
        .padding(.vertical, isCompact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0.1), value: isCompact)
        .animation(.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0.1), value: hasText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleEffect(appeared ? 1.0 : 0.5, anchor: .top)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0.1), value: appeared)
    }

    // MARK: - Notch mode body (Dynamic Island extending from hardware notch)

    private var notchBody: some View {
        VStack(spacing: 0) {
            // Main row: icon on left, spacer, waveform/timer on right
            HStack(spacing: 0) {
                // Left side: icon
                Group {
                    if isEnhancing {
                        processingSpinner
                    } else {
                        kazeIcon
                    }
                }
                .padding(.leading, 20)

                Spacer(minLength: 12)

                // Right side: waveform bars
                Group {
                    if isEnhancing {
                        processingBars
                            .transition(.opacity)
                    } else {
                        notchWaveformBars
                            .transition(.opacity)
                    }
                }
                .padding(.trailing, 20)
            }
            .animation(.easeInOut(duration: 0.25), value: isEnhancing)
            .frame(height: 32)

            // Expanded: show transcription text below
            if hasText {
                transcriptionTextRow(maxWidth: 320)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: notchContentWidth)
        .background(
            NotchShape(topCornerRadius: notchTopCornerRadius, bottomCornerRadius: notchBottomCornerRadius)
                .fill(.black)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1), value: isCompact)
        .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1), value: hasText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleEffect(x: appeared ? 1.0 : 0.0, y: 1.0, anchor: .top)
        .clipped()
        .animation(.spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0.1), value: appeared)
    }

    /// Width of the notch content — wider when expanded with text.
    private var notchContentWidth: CGFloat {
        isCompact ? 280 : 360
    }

    // MARK: - Shared components

    private var kazeIcon: some View {
        Image("kaze-icon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .foregroundStyle(.white.opacity(0.9))
            .transition(.opacity)
    }

    private func transcriptionTextRow(maxWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Text(transcribedText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .id(textScrollID)

                    Spacer().frame(width: 4)
                }
            }
            .frame(maxWidth: maxWidth)
            .mask(
                HStack(spacing: 0) {
                    if textOverflows {
                        LinearGradient(
                            colors: [.clear, .white],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 16)
                        .transition(.opacity)
                    }
                    Color.white
                }
            )
            .onChange(of: transcribedText) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(textScrollID, anchor: .trailing)
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: - Waveform bars (recording state)

    private var waveformBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white)
                    .frame(width: 2.5, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
            }
        }
        .frame(height: 24)
    }

    // MARK: - Notch waveform bars (red, fewer bars, compact)

    private let notchBarCount = 5

    private var notchWaveformBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<notchBarCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.red)
                    .frame(width: 3, height: notchBarHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
            }
        }
        .frame(height: 20)
    }

    private func notchBarHeight(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        // Use a subset of phases so bars still animate independently
        let phaseIndex = index * 3 // spread across the 16 phases
        let phase = phases[min(phaseIndex, barCount - 1)]
        let sine = (sin(phase) + 1) / 2
        let minH: CGFloat = 4
        let maxH: CGFloat = 18

        if isRecording {
            let driven = minH + (maxH - minH) * level * CGFloat(sine * 0.7 + 0.3)
            return max(minH, driven)
        } else {
            return minH + (maxH * 0.15) * CGFloat(sine)
        }
    }

    // MARK: - Processing bars (enhancing state)

    private var processingBars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(processingBarOpacity(for: index)))
                    .frame(width: 2.5, height: processingBarHeight(for: index))
            }
        }
        .frame(height: 24)
    }

    // MARK: - Processing spinner

    private var processingSpinner: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(spinAngle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            }
    }

    // MARK: - Bar helpers

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        let phase = phases[index]
        let sine = (sin(phase) + 1) / 2
        let minH: CGFloat = 3
        let maxH: CGFloat = 22

        if isRecording {
            let driven = minH + (maxH - minH) * level * CGFloat(sine * 0.7 + 0.3)
            return max(minH, driven)
        } else {
            return minH + (maxH * 0.15) * CGFloat(sine)
        }
    }

    /// Gentle wave pattern for processing bars — subtle, low variance
    private func processingBarHeight(for index: Int) -> CGFloat {
        let phase = phases[index]
        let sine = (sin(phase) + 1) / 2
        let minH: CGFloat = 6
        let maxH: CGFloat = 10
        return minH + (maxH - minH) * CGFloat(sine)
    }

    /// Shimmer opacity for processing bars
    private func processingBarOpacity(for index: Int) -> Double {
        let phase = phases[index]
        let sine = (sin(phase * 1.2) + 1) / 2
        return 0.35 + 0.4 * sine
    }

    // MARK: - Animation timer (Fix #8: use DisplayLink-driven TimelineView instead of manual Timer)

    private func startAnimating() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [self] _ in
            let speed: Double = isRecording ? 0.18 : (isEnhancing ? 0.08 : 0.05)
            for i in 0..<barCount {
                phases[i] += speed + Double(i) * 0.008
            }
        }
        // Schedule on common run loop mode so it fires during tracking
        if let timer = animTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopAnimating() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - Notch Shape (Dynamic Island style)
// Copied directly from teleprompter app's NotchContentView.swift

/// Notch shape with concave "ear" curves at the top corners and convex rounded bottom corners.
/// The top corners use quadratic Bezier curves that bow outward, creating the inverse
/// rounded corner effect seen on the MacBook notch / Dynamic Island.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 10, bottomCornerRadius: CGFloat = 16) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at the top-left corner of the bounding rect
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left "ear": concave quadratic curve from (minX, minY) inward
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // Left edge going down to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // Bottom-left convex rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // Bottom-right convex rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // Right edge going up to top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        // Top-right "ear": concave quadratic curve outward to (maxX, minY)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        // Close along the top edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        WaveformView(audioLevel: 0.6, isRecording: true, transcribedText: "Hello world this is a long test")
        WaveformView(audioLevel: 0, isRecording: false, transcribedText: "", isEnhancing: true)
        WaveformView(audioLevel: 0.6, isRecording: true, transcribedText: "Hello world this is a long test", notchMode: true)
        WaveformView(audioLevel: 0, isRecording: false, transcribedText: "", isEnhancing: true, notchMode: true)
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
