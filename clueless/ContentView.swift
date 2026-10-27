import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SessionCoordinator
    var body: some View {
        @Bindable var settings = session.settings
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: session.symbol).font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("clueless").font(.headline)
                    Text("\(session.status) · \(session.processingState.rawValue.capitalized)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(session.captureState == .capturing ? .green : .secondary).frame(width: 8, height: 8)
            }
            Divider()
            Picker("Mode", selection: Binding(get: { session.settings.mode }, set: { session.changeMode($0) })) {
                ForEach(RouterMode.allCases) { Text($0.rawValue).tag($0) }
            }.disabled(session.busy)
            Picker("Source", selection: $settings.source) {
                ForEach(AudioSource.allCases) { Text($0.rawValue).tag($0) }
            }.disabled(session.captureState == .capturing || session.busy || session.settings.mode == .virtualMicrophone)
            Toggle("Always Listening", isOn: Binding(get: { session.intent.persistent }, set: { session.setPersistent($0) }))
                .toggleStyle(.switch).disabled(session.busy)
            ProgressView(value: min(Double(session.audioLevel) * 5, 1)).tint(.green)
            Button(session.intent.wanted ? "Stop Listening" : "Start Listening") { session.toggleListening() }
                .buttonStyle(.borderedProminent).disabled(session.busy)
            if let error = session.errorMessage { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Divider()
            Button("Show Floating Window") {
                dismiss()
                DispatchQueue.main.async {
                    NSApp.activate()
                    session.showPanel?(true)
                }
            }
            Button("Center Floating Window on This Screen") { session.centerPanel?() }
            Button("Session History") { session.showHistory() }
            if session.settings.mode.supportsChat {
                Button("Read Screen Region…") { session.readScreen() }.disabled(session.screenReadState != .idle)
                if session.screenReadState != .idle {
                    Text("Screen: \(session.screenReadState.rawValue.capitalized)…").font(.caption)
                    Button("Cancel Screen Reading") { session.cancelScreenRead() }
                }
                if let error = session.screenReadError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Button("Settings…") { NSApp.activate(); openSettings() }
                Spacer()
                Button("Stop All") { session.stopAll() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }.padding(18).frame(width: 340)
    }
}

struct FloatingPanelView: View {
    @Bindable var session: SessionCoordinator
    var presentFilePanel: (NSSavePanel, @escaping (NSApplication.ModalResponse) -> Void) -> Void
    @State private var tab = "Transcript"
    @State private var compact = false
    @State private var prompt = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: session.symbol).foregroundStyle(session.captureState == .capturing ? .green : .secondary)
                Text(session.settings.mode.rawValue).font(.headline)
                Spacer()
                Text(session.status).font(.caption).foregroundStyle(.secondary)
                Button { compact.toggle() } label: { Image(systemName: compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }
                    .help("Compact / expanded")
                Button { session.togglePanel?() } label: { Image(systemName: "xmark") }.help("Hide; keep session running")
            }.padding()
            Divider()
            if compact {
                Text(session.replies.last?.text ?? session.history.entries.last?.text ?? "Ready when you are.")
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).padding()
            } else {
                Picker("Content", selection: $tab) {
                    Text("Transcript").tag("Transcript")
                    Text("Responses").tag("Responses")
                    Text("Context").tag("Context")
                }.pickerStyle(.segmented).padding([.horizontal, .top])
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if tab == "Context" {
                                contextEditor
                            } else if tab == "Transcript" {
                                if session.history.entries.isEmpty { emptyState("Your conversation, in text", detail: "Start listening to see the transcript here. Audio is never saved to disk.") }
                                ForEach(session.history.entries) { entry in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(entry.date, style: .time)
                                            if !entry.confirmed { Text("Live · provisional") }
                                        }.font(.caption2).foregroundStyle(.secondary)
                                        Text(entry.text.isEmpty ? "…" : entry.text).foregroundStyle(entry.confirmed ? .primary : .secondary).textSelection(.enabled)
                                    }
                                }
                            } else {
                                if session.replies.isEmpty { emptyState("A little help, on demand", detail: "Ask about the captured conversation in Live Transcription or Auto Answer. Auto Answer also responds or summarizes at each pause.") }
                                ForEach(session.replies) { reply in
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack {
                                            Label("AI suggestion", systemImage: "sparkles")
                                            Spacer()
                                            Text(reply.date, style: .time)
                                            Button { session.copy(reply.text) } label: { Image(systemName: "doc.on.doc") }
                                        }.font(.caption).foregroundStyle(.secondary)
                                        Text(reply.prompt).font(.caption).foregroundStyle(.secondary)
                                        Text(reply.text.isEmpty ? "Thinking…" : reply.text).textSelection(.enabled)
                                        Text(reply.status).font(.caption2).foregroundStyle(.secondary)
                                    }.padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding()
                    }
                    .onChange(of: session.history.entries.last?.text) { if session.settings.autoScroll { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: session.replies.last?.text) { if session.settings.autoScroll { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                if session.settings.mode.supportsChat {
                    HStack {
                        TextField("Ask about the conversation or context…", text: $prompt).textFieldStyle(.roundedBorder)
                            .onSubmit { sendPrompt() }
                        Button { sendPrompt() } label: { Image(systemName: "arrow.up.circle.fill") }.disabled(session.generating)
                    }.padding(.horizontal).padding(.bottom, 10)
                }
            }
            Divider()
            HStack {
                Button(session.captureState == .capturing ? "Pause" : "Listen") {
                    if session.captureState == .capturing { session.pause() } else { session.toggleListening() }
                }.disabled(session.busy)
                Button("Copy") { session.copy(tab == "Transcript" ? session.history.confirmedText : session.replies.map(\.text).joined(separator: "\n\n")) }.disabled(tab == "Context")
                Button("Export") { exportTranscript() }
                Spacer()
                if session.generating { Button("Stop Response") { session.cancelResponse() } }
                if session.settings.mode.supportsChat {
                    Button("Generate") { tab = "Responses"; session.generate("Suggest a concise response to the latest captured question.") }.disabled(session.generating)
                }
            }.font(.caption).padding(12)
            if let error = session.errorMessage { Text(error).font(.caption).foregroundStyle(.red).padding([.horizontal, .bottom]) }
        }.frame(minWidth: 330, minHeight: 150).background(.regularMaterial)
            .onChange(of: session.historyPresentationID) {
                tab = "Transcript"
                compact = false
            }
    }
    private var contextEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Response context").font(.headline)
            Text("Paste notes or add TXT, Markdown, or PDFs with selectable text. Reference text is sent to OpenAI with each response. It stays in memory until cleared or you quit.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding(get: { session.responseContext.text }, set: { value in
                do { try session.responseContext.setText(value) }
                catch { session.errorMessage = error.localizedDescription }
            })).frame(minHeight: 140).border(.quaternary)
                .accessibilityLabel("Pasted response context")
            Text("\(session.responseContext.characterCount) / 48,000 characters · 10 MB per file")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(session.importingContext ? "Importing…" : "Add Files…") { importContextFiles() }
                    .disabled(session.importingContext)
                Button("Clear Context", role: .destructive) { session.clearContext() }
            }
            ForEach(session.responseContext.files) { file in
                HStack {
                    VStack(alignment: .leading) {
                        Text(file.name)
                        Text("\(file.text.count) characters").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove") { session.responseContext.remove(file.id) }
                        .accessibilityLabel("Remove \(file.name)")
                }
            }
            screenContextEditor
        }
    }
    private var screenContextEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Screen Text").font(.headline)
            Text("Recognized text is automatically used in subsequent responses, including Auto Answer. Images are processed locally. Captures do not update when the screen changes.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Read Screen Region…") { session.readScreen() }
                    .disabled(!session.settings.mode.supportsChat || session.screenReadState != .idle)
                if session.screenReadState != .idle {
                    ProgressView().controlSize(.small)
                    Text("\(session.screenReadState.rawValue.capitalized)…").font(.caption)
                    Button("Cancel") { session.cancelScreenRead() }
                }
            }
            if let screen = session.responseContext.screen {
                HStack {
                    Text(screen.displayName)
                    Text(screen.capturedAt, style: .time)
                }.font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { session.responseContext.screen?.text ?? "" }, set: { session.editScreenText($0) }))
                    .frame(minHeight: 140).border(.quaternary)
                    .accessibilityLabel("Recognized screen text")
                HStack {
                    Text("\(screen.text.count) characters").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy") { session.copy(screen.text) }
                    Button("Remove") { session.removeScreenContext() }
                }
            }
            if let error = session.screenReadError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
    }
    private func importContextFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
        presentFilePanel(panel) { result in
            guard result == .OK else { return }
            session.importContext(panel.urls)
        }
    }
    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.tint)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }.padding(.vertical, 30)
    }
    private func sendPrompt() { tab = "Responses"; session.generate(prompt); if session.generating { prompt = "" } }
    private func exportTranscript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "clueless Transcript.txt"
        presentFilePanel(panel) { result in
            guard result == .OK, let url = panel.url else { return }
            do { try session.history.confirmedText.write(to: url, atomically: true, encoding: .utf8) }
            catch { session.errorMessage = error.localizedDescription }
        }
    }
}

struct RouterSettingsView: View {
    @Bindable var session: SessionCoordinator
    var applyShortcuts: () -> Void
    var applyPanel: () -> Void
    @State private var key = ""
    @State private var keyStatus = ""
    @State private var devices: [AudioDevice] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        @Bindable var settings = session.settings
        TabView {
            Form {
                Toggle("Launch at Login", isOn: $launchAtLogin).onChange(of: launchAtLogin) {
                    do { if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { session.errorMessage = error.localizedDescription }
                }
                Text("Listening never starts automatically on launch.").font(.caption).foregroundStyle(.secondary)
                Toggle("Open floating window when listening", isOn: $settings.openPanel)
                Toggle("Show on all Spaces", isOn: $settings.allSpaces).onChange(of: settings.allSpaces, applyPanel)
                Toggle("Auto-scroll results", isOn: $settings.autoScroll)
                LabeledContent("Opacity") { Slider(value: $settings.opacity, in: 0.5...1) }.onChange(of: settings.opacity, applyPanel)
                Text("History stays in memory until you clear it or quit. Windows stay on top. Show Floating Window preserves its position; use Center Floating Window to move it to the current screen.").font(.caption).foregroundStyle(.secondary)
                Button("Clear Session History", role: .destructive) { session.clearHistory() }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Picker("Source", selection: $settings.source) { ForEach(AudioSource.allCases) { Text($0.rawValue).tag($0) } }
                    .disabled(session.captureState == .capturing || session.busy || settings.mode == .virtualMicrophone)
                Picker("Virtual output", selection: $settings.virtualDeviceUID) {
                    Text("First available BlackHole").tag("")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }.disabled(session.captureState == .capturing || session.busy)
                Button("Refresh Devices") { devices = VirtualDevices.list() }
                if devices.isEmpty {
                    Text("BlackHole is not installed or available.").foregroundStyle(.orange)
                    Link("BlackHole setup instructions", destination: URL(string: "https://github.com/ExistentialAudio/BlackHole#installation-instructions")!)
                }
                Text("Select BlackHole as the microphone in the receiving app. Keep your normal output on headphones. clueless does not change system defaults or replay audio to your speakers. Do not enable monitoring of BlackHole in the receiving app.").font(.callout)
                Text("Microphone uses the macOS default input. Mixed sources and per-app selection are planned for phase two.").font(.caption).foregroundStyle(.secondary)
                Button("Open Sound Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) }
            }.formStyle(.grouped).tabItem { Label("Audio", systemImage: "waveform") }
            Form {
                SecureField("API key", text: $key)
                HStack {
                    Button("Save to Keychain") { do { try KeychainService.save(key); key = ""; keyStatus = "Saved securely in Keychain." } catch { keyStatus = error.localizedDescription } }
                    Button("Remove Key") { do { session.stopAll(); try KeychainService.delete(); key = ""; keyStatus = "Key removed." } catch { keyStatus = error.localizedDescription } }
                    Button("Test Connection") {
                        Task {
                            do {
                                guard let stored = try KeychainService.read() else { throw RouterError("Save a key first.") }
                                try await TextGenerationClient.testConnection(key: stored)
                                keyStatus = "Connected. Model availability depends on your account."
                            } catch { keyStatus = error.localizedDescription }
                        }
                    }
                }
                Text(keyStatus).font(.caption)
                TextField("Transcription model", text: $settings.transcriptionModel)
                TextField("Response model", text: $settings.responseModel)
                Text("Transcription settings take effect the next time you start listening.").font(.caption).foregroundStyle(.secondary)
                TextField("Languages (e.g. es,en; blank = automatic)", text: $settings.languages)
                Text("Live Transcription answers when you ask in the chat. Auto Answer automatically answers questions or summarizes the turn after each speech pause (about 0.8 seconds), or when you release Push-to-Listen. Responses run one at a time.").font(.caption).foregroundStyle(.secondary)
                Text("System prompt")
                TextEditor(text: $settings.systemPrompt).frame(height: 65).border(.quaternary)
                Stepper("Upload limit: \(Int(settings.maxMinutes)) minutes per session", value: $settings.maxMinutes, in: 1...480, step: 1)
                Text("Audio sent: \(session.sentSeconds / 60, specifier: "%.1f") min. This local time limit is not a provider billing cap. Monetary cost is not estimated.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).tabItem { Label("OpenAI", systemImage: "sparkles") }
            Form {
                Text("All shortcuts use Control + Option plus the selected key. Hold activates only while pressed.").font(.callout)
                ForEach(GlobalHotkeyManager.names, id: \.self) { name in
                    Picker(name, selection: Binding(get: { settings.shortcuts[name] ?? UInt32.max }, set: { settings.shortcuts[name] = $0 })) {
                        Text("Unassigned").tag(UInt32.max)
                        ForEach(GlobalHotkeyManager.keys, id: \.1) { Text($0.0).tag($0.1) }
                    }
                }
                Button("Apply Shortcuts", action: applyShortcuts)
                if let error = session.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
                Text("Registration reports known conflicts. Some shortcuts reserved by macOS or other apps may still take precedence.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).tabItem { Label("Shortcuts", systemImage: "keyboard") }
            Form {
                Text("System audio and Read Screen Region require Screen & System Audio Recording permission. Screen text is recognized locally; screenshots are never saved or uploaded. Recognized text is sent to OpenAI only when generating responses, including Auto Answer. No Accessibility permission is needed for screen reading. Microphone permission is requested only for the Microphone source. Global shortcuts use Carbon and do not monitor typed text.")
                Button("Screen & System Audio Recording Settings") { openPrivacy("Privacy_ScreenCapture") }
                Button("Microphone Settings") { openPrivacy("Privacy_Microphone") }
                Text("Captured audio is sent to OpenAI only in AI modes and after session consent. Virtual Microphone is entirely local. No raw audio or transcript is saved automatically. Exported text is saved only where you choose.")
                Text("Dictation currently transcribes and copies text. Automatic insertion and Accessibility permission are deferred to phase two.").foregroundStyle(.secondary)
            }.formStyle(.grouped).tabItem { Label("Privacy", systemImage: "hand.raised") }
        }.frame(width: 650, height: 570)
            .onAppear {
                devices = VirtualDevices.list()
                do { keyStatus = try KeychainService.read() == nil ? "No key saved." : "A key is stored in Keychain." }
                catch { keyStatus = error.localizedDescription }
            }
    }
    private func openPrivacy(_ pane: String) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!) }
}
