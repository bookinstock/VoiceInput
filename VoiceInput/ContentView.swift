import SwiftUI
import Carbon

/// Main content view for settings
struct ContentView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @ObservedObject var settings = AppSettings.shared
    @StateObject private var hotKeyRecorder = HotKeyRecorder()
    
    @State private var showingHotKeyRecorder = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Status section
            statusSection
            
            Divider()
            
            // Settings sections
            ScrollView {
                VStack(spacing: 16) {
                    languageSection
                    hotKeySection
                    permissionsSection
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 320, height: 400)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text("VoiceInput")
                .font(.headline)
            
            Spacer()
            
            // Recording indicator
            if appDelegate.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.5), lineWidth: 2)
                                .scaleEffect(1.5)
                                .opacity(0.5)
                        )
                    Text("录音中")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: appDelegate.isRecording)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(spacing: 8) {
            // Big record button
            Button(action: {
                appDelegate.toggleRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(appDelegate.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 64, height: 64)
                        .shadow(color: (appDelegate.isRecording ? Color.red : Color.accentColor).opacity(0.4), radius: 8)
                    
                    Image(systemName: appDelegate.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 12)
            
            Text(appDelegate.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Last transcribed text
            if !appDelegate.lastTranscribedText.isEmpty {
                Text(appDelegate.lastTranscribedText)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .lineLimit(2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Language Section
    
    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("识别语言", systemImage: "globe")
                .font(.subheadline.weight(.medium))
            
            Picker("语言", selection: $settings.language) {
                ForEach(RecognitionLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: settings.language) { newValue in
                appDelegate.speechRecognizer.changeLanguage(to: newValue)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Hotkey Section
    
    private var hotKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("快捷键", systemImage: "keyboard")
                .font(.subheadline.weight(.medium))
            
            HStack {
                Text("触发录音")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if showingHotKeyRecorder {
                    HStack {
                        if hotKeyRecorder.isRecording {
                            Text("按下快捷键组合...")
                                .foregroundColor(.orange)
                                .font(.caption)
                        } else if let config = hotKeyRecorder.recordedConfig {
                            Text(config.displayString)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        Button("保存") {
                            hotKeyRecorder.applyRecordedConfig()
                            showingHotKeyRecorder = false
                        }
                        .disabled(hotKeyRecorder.recordedConfig == nil)
                        
                        Button("取消") {
                            hotKeyRecorder.stopRecording()
                            showingHotKeyRecorder = false
                        }
                    }
                } else {
                    Button(action: {
                        showingHotKeyRecorder = true
                        hotKeyRecorder.startRecording()
                    }) {
                        Text(settings.hotKeyConfig.displayString)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlColor))
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Text("按下快捷键开始录音，再按停止")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Permissions Section
    
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("权限状态", systemImage: "lock.shield")
                .font(.subheadline.weight(.medium))
            
            VStack(spacing: 6) {
                permissionRow(
                    title: "麦克风",
                    isGranted: appDelegate.speechRecognizer.isAuthorized,
                    action: { openSystemPreferences("Privacy_Microphone") }
                )
                
                permissionRow(
                    title: "语音识别",
                    isGranted: appDelegate.speechRecognizer.isAuthorized,
                    action: { openSystemPreferences("Privacy_SpeechRecognition") }
                )
                
                permissionRow(
                    title: "辅助功能",
                    isGranted: TextInputSimulator.shared.checkAccessibilityPermissions(),
                    action: { openSystemPreferences("Privacy_Accessibility") }
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func permissionRow(title: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(isGranted ? .green : .orange)
            
            Text(title)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if !isGranted {
                Button("授权") {
                    action()
                }
                .font(.caption)
            }
        }
    }
    
    private func openSystemPreferences(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button(action: {
                NSApp.terminate(nil)
            }) {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.secondary)
            
            Spacer()
            
            Text("v1.0")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppDelegate())
    }
}

