import SwiftUI
import AppKit

/// Floating panel window for recording feedback
class FloatingPanelController: NSObject, ObservableObject {
    
    static let shared = FloatingPanelController()
    
    private var window: NSWindow?
    private var hostingView: NSHostingView<FloatingPanelView>?
    
    @Published var isVisible: Bool = false
    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false
    
    /// Callback when user clicks confirm button
    var onConfirm: (() -> Void)?
    /// Callback when user clicks cancel button
    var onCancel: (() -> Void)?
    
    private override init() {
        super.init()
    }
    
    func show() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.window == nil {
                self.createWindow()
            }
            
            self.isVisible = true
            self.isRecording = true
            self.transcribedText = ""
            self.window?.orderFront(nil)
            
            // Animate in
            self.window?.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.window?.animator().alphaValue = 1
            }
        }
    }
    
    func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isRecording = false
            
            // Animate out
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.window?.animator().alphaValue = 0
            } completionHandler: {
                self.window?.orderOut(nil)
                self.isVisible = false
            }
        }
    }
    
    func updateText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.transcribedText = text
        }
    }
    
    private func createWindow() {
        // Get screen size
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        
        // Window size
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 160
        
        // Position at bottom center
        let windowX = screenRect.origin.x + (screenRect.width - windowWidth) / 2
        let windowY = screenRect.origin.y + 60
        
        let windowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        
        // Create window
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Create SwiftUI view
        let contentView = FloatingPanelView(controller: self)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        hostingView.autoresizingMask = [.width, .height]
        
        window.contentView = hostingView
        
        self.window = window
        self.hostingView = hostingView
    }
}

/// SwiftUI view for the floating panel
struct FloatingPanelView: View {
    @ObservedObject var controller: FloatingPanelController
    
    var body: some View {
        VStack(spacing: 12) {
            // Waveform animation
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    WaveformBar(index: index, isAnimating: controller.isRecording)
                }
            }
            .frame(height: 36)
            
            // Transcribed text
            if !controller.transcribedText.isEmpty {
                Text(controller.transcribedText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else if controller.isRecording {
                Text("正在聆听...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Action buttons (only show when there's text)
            if !controller.transcribedText.isEmpty {
                HStack(spacing: 16) {
                    // Cancel button
                    Button(action: {
                        controller.onCancel?()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                            Text("取消")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // OK button
                    Button(action: {
                        controller.onConfirm?()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                            Text("采用")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.4, green: 0.6, blue: 1.0),
                                            Color(red: 0.5, green: 0.4, blue: 1.0)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.2, green: 0.2, blue: 0.25),
                            Color(red: 0.15, green: 0.15, blue: 0.2)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Individual waveform bar with animation
struct WaveformBar: View {
    let index: Int
    let isAnimating: Bool
    
    @State private var height: CGFloat = 8
    
    private let minHeight: CGFloat = 8
    private let maxHeight: CGFloat = 35
    
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.4, green: 0.6, blue: 1.0),
                        Color(red: 0.6, green: 0.4, blue: 1.0)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 6, height: height)
            .animation(
                Animation
                    .easeInOut(duration: 0.3 + Double(index) * 0.1)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.1),
                value: height
            )
            .onAppear {
                if isAnimating {
                    startAnimation()
                }
            }
            .onChange(of: isAnimating) { newValue in
                if newValue {
                    startAnimation()
                } else {
                    stopAnimation()
                }
            }
    }
    
    private func startAnimation() {
        height = CGFloat.random(in: minHeight...maxHeight)
        
        // Continuously randomize height
        Timer.scheduledTimer(withTimeInterval: 0.3 + Double(index) * 0.1, repeats: true) { timer in
            if isAnimating {
                withAnimation(.easeInOut(duration: 0.3)) {
                    height = CGFloat.random(in: minHeight...maxHeight)
                }
            } else {
                timer.invalidate()
            }
        }
    }
    
    private func stopAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            height = minHeight
        }
    }
}

// MARK: - Preview

struct FloatingPanelView_Previews: PreviewProvider {
    static var previews: some View {
        FloatingPanelView(controller: FloatingPanelController.shared)
            .frame(width: 400, height: 120)
            .background(Color.black)
    }
}

