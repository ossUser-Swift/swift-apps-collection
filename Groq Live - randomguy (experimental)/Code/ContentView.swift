import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = AICallViewModel()
    
    var body: some View {
        ZStack {
            // Background
            Color(hexString: "262626")
                .ignoresSafeArea()
            
            if viewModel.needsAPIKeys {
                apiKeySetupView
            } else {
                audioCallView
            }
        }
        .alert("Switching to Backup Voice", isPresented: $viewModel.showFallbackAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("ElevenLabs credits exhausted. Using Apple's native voice as backup.")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $viewModel.showSettings) {
            settingsView
        }
        .onAppear {
            viewModel.requestPermissions()
            if !viewModel.needsAPIKeys {
                viewModel.startContinuousListening()
            }
        }
    }
    
    var apiKeySetupView: some View {
        VStack(spacing: 25) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
            
            Text("API Configuration")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Enter your API keys to get started")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Groq API Key")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.caption)
                    
                    TextField("gsk_...", text: $viewModel.groqAPIKeyInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("ElevenLabs API Key")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.caption)
                    
                    TextField("Enter ElevenLabs key", text: $viewModel.elevenLabsAPIKeyInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .padding(.horizontal, 40)
            
            Button(action: {
                viewModel.saveAPIKeys()
            }) {
                Text("Start Call")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canSaveAPIKeys ? Color.green : Color.gray)
                    .cornerRadius(15)
            }
            .disabled(!viewModel.canSaveAPIKeys)
            .padding(.horizontal, 40)
        }
        .padding()
    }
    
    var audioCallView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 20) {
                ZStack {
                    // Loading spinner
                    if viewModel.isProcessing && !viewModel.isPlayingAudio {
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(Color.white.opacity(0.6), lineWidth: 3)
                            .frame(width: 270, height: 270)
                            .rotationEffect(Angle(degrees: viewModel.spinnerRotation))
                    }
                    
                    Image("images")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                }
                
                HStack(spacing: 4) {
                    ForEach(0..<20, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 3, height: viewModel.waveformHeights[index])
                    }
                }
                .frame(height: 40)
                .padding(.top, 10)
            }
            
            Spacer()
            
            Button(action: {
                viewModel.showSettings = true
            }) {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .foregroundColor(.white.opacity(0.7))
                .font(.caption)
            }
            .padding(.bottom, 30)
        }
    }
    
    var settingsView: some View {
        NavigationView {
            Form {
                Section(header: Text("API Keys")) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Groq API Key")
                            .font(.caption)
                        TextField("gsk_...", text: $viewModel.groqAPIKeyInput)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ElevenLabs API Key")
                            .font(.caption)
                        TextField("Enter key", text: $viewModel.elevenLabsAPIKeyInput)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
                
                Section(header: Text("Voice")) {
                    Picker("ElevenLabs Voice", selection: $viewModel.selectedVoice) {
                        ForEach(viewModel.availableVoices, id: \.id) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(
                leading: Button("Cancel") {
                    viewModel.showSettings = false
                },
                trailing: Button("Save") {
                    viewModel.saveSettings()
                }
            )
        }
    }
}

@MainActor
class AICallViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var statusMessage = "Waiting to start..."
    @Published var transcribedText = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showFallbackAlert = false
    @Published var needsAPIKeys = true
    @Published var groqAPIKeyInput = ""
    @Published var elevenLabsAPIKeyInput = ""
    @Published var showSettings = false
    @Published var selectedVoice = "21m00Tcm4TlvDq8ikWAM"
    @Published var waveformHeights: [CGFloat] = Array(repeating: 10, count: 20)
    @Published var spinnerRotation: Double = 0
    @Published var isPlayingAudio = false
    
    private var groqAPIKey = ""
    private var elevenLabsAPIKey = ""
    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayer?
    private var silenceTimer: Task<Void, Never>?
    private var lastAudioLevelTime = Date()
    private var hasStartedSpeaking = false
    private var recordedAudioURL: URL?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechCompletion: CheckedContinuation<Void, Never>?
    private var waveformTimer: Timer?
    private var spinnerTimer: Timer?
    
    let availableVoices: [(id: String, name: String)] = [
        ("21m00Tcm4TlvDq8ikWAM", "Rachel"),
        ("AZnzlk1XvdvUeBnXmlld", "Domi"),
        ("EXAVITQu4vr4xnSDxMaL", "Bella"),
        ("ErXwobaYiN019PkySvjV", "Antoni"),
        ("MF3mGyEYCl7XYWbV9V6O", "Elli"),
        ("TxGEqnHWrfWFTfGW9XjX", "Josh"),
        ("VR6AewLTigWG4xSOukaG", "Arnold"),
        ("pNInz6obpgDQGcFmaJgB", "Adam"),
        ("yoZ06aMxZJJ28mfd3POQ", "Sam"),
        ("onwK4e9ZLuTAKqWW03F9", "Serena")
    ]
    
    var canSaveAPIKeys: Bool {
        !groqAPIKeyInput.isEmpty && !elevenLabsAPIKeyInput.isEmpty
    }
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        loadSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.startWaveformMonitoring()
        }
    }
    
    func loadSettings() {
        if let groqKey = UserDefaults.standard.string(forKey: "groqAPIKey"),
           let elevenKey = UserDefaults.standard.string(forKey: "elevenLabsAPIKey") {
            groqAPIKey = groqKey
            elevenLabsAPIKey = elevenKey
            groqAPIKeyInput = groqKey
            elevenLabsAPIKeyInput = elevenKey
            needsAPIKeys = false
        }
        
        if let voice = UserDefaults.standard.string(forKey: "selectedVoice") {
            selectedVoice = voice
        }
    }
    
    func saveAPIKeys() {
        groqAPIKey = groqAPIKeyInput
        elevenLabsAPIKey = elevenLabsAPIKeyInput
        UserDefaults.standard.set(groqAPIKey, forKey: "groqAPIKey")
        UserDefaults.standard.set(elevenLabsAPIKey, forKey: "elevenLabsAPIKey")
        needsAPIKeys = false
        startContinuousListening()
    }
    
    func saveSettings() {
        groqAPIKey = groqAPIKeyInput
        elevenLabsAPIKey = elevenLabsAPIKeyInput
        UserDefaults.standard.set(groqAPIKey, forKey: "groqAPIKey")
        UserDefaults.standard.set(elevenLabsAPIKey, forKey: "elevenLabsAPIKey")
        UserDefaults.standard.set(selectedVoice, forKey: "selectedVoice")
        showSettings = false
    }
    
    func startContinuousListening() {
        startRecording()
    }
    
    func requestPermissions() {
        AVAudioApplication.requestRecordPermission { allowed in
            if !allowed {
                DispatchQueue.main.async {
                    self.errorMessage = "Microphone permission is required"
                    self.showError = true
                }
            }
        }
    }
    
    func startRecording() {
        transcribedText = ""
        lastAudioLevelTime = Date()
        hasStartedSpeaking = false
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            let tempDir = FileManager.default.temporaryDirectory
            recordedAudioURL = tempDir.appendingPathComponent("recording_\(UUID().uuidString).wav")
            
            guard let audioURL = recordedAudioURL else { return }
            try? FileManager.default.removeItem(at: audioURL)
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            let audioFile = try AVAudioFile(forWriting: audioURL, settings: recordingFormat.settings)
            
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                try? audioFile.write(from: buffer)
                
                let channelData = buffer.floatChannelData?[0]
                let frameLength = Int(buffer.frameLength)
                
                var sum: Float = 0
                if let data = channelData {
                    for i in 0..<frameLength {
                        sum += abs(data[i])
                    }
                }
                let avgLevel = sum / Float(frameLength)
                
                if avgLevel > 0.01 {
                    DispatchQueue.main.async {
                        if !self.hasStartedSpeaking {
                            self.hasStartedSpeaking = true
                            self.statusMessage = "Listening..."
                        }
                        self.lastAudioLevelTime = Date()
                        self.silenceTimer?.cancel()
                        self.startSilenceTimer()
                    }
                }
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            statusMessage = "Waiting for you to speak..."
            
        } catch {
            errorMessage = "Recording failed: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func startSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            if self.isRecording && self.hasStartedSpeaking && Date().timeIntervalSince(self.lastAudioLevelTime) >= 2.0 {
                self.stopRecording()
            }
        }
    }
    
    func stopRecording() {
        silenceTimer?.cancel()
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        isRecording = false
        
        if hasStartedSpeaking, let audioURL = recordedAudioURL {
            processWithWhisper(audioURL: audioURL)
        } else {
            statusMessage = "No speech detected."
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    startContinuousListening()
                }
            }
        }
    }
    
    private func processWithWhisper(audioURL: URL) {
        isProcessing = true
        isPlayingAudio = false
        statusMessage = "Transcribing..."
        startSpinner()
        
        Task {
            do {
                let transcription = try await transcribeWithWhisper(audioURL: audioURL)
                transcribedText = transcription
                
                statusMessage = "Getting AI response..."
                let aiResponse = try await sendToGroq(text: transcription)
                
                statusMessage = "Converting to speech..."
                
                do {
                    let audioData = try await convertToSpeechElevenLabs(text: aiResponse)
                    stopSpinner()
                    isPlayingAudio = true
                    statusMessage = "Playing response..."
                    await playAudio(data: audioData)
                } catch {
                    print("ElevenLabs TTS failed, falling back to Apple: \(error.localizedDescription)")
                    showFallbackAlert = true
                    stopSpinner()
                    isPlayingAudio = true
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await speakWithAppleTTS(text: aiResponse)
                }
                
                isProcessing = false
                isPlayingAudio = false
                
            } catch {
                errorMessage = "Error: \(error.localizedDescription)"
                showError = true
                statusMessage = "Error occurred."
                isProcessing = false
                isPlayingAudio = false
                stopSpinner()
                
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    startContinuousListening()
                }
            }
        }
    }
    
    private func transcribeWithWhisper(audioURL: URL) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var data = Data()
        
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        data.append("whisper-large-v3\r\n".data(using: .utf8)!)
        
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        data.append(try Data(contentsOf: audioURL))
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = data
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "WhisperAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Whisper API error: \(errorText)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        let text = json?["text"] as? String
        
        return text ?? ""
    }
    
    private func sendToGroq(text: String) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "groq/compound",
            "messages": [
                ["role": "system", "content": "Messages must always be below 10000 characters, including spaces. Format your responses in a natural, conversational way suitable for text-to-speech - avoid special characters, formatting symbols, bullet points, or anything that wouldn't sound natural when spoken aloud. Write as if you're having a verbal conversation."],
                ["role": "user", "content": text]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GroqAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Groq API error: \(errorText)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String
        
        return content ?? "No response"
    }
    
    private func convertToSpeechElevenLabs(text: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(selectedVoice)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ElevenLabsAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "ElevenLabs API error: \(errorText)"])
        }
        
        return data
    }
    
    private func playAudio(data: Data) async {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true)
            
            audioPlayer = try AVAudioPlayer(data: data)
            guard let player = audioPlayer else { return }
            
            player.delegate = self
            player.isMeteringEnabled = true
            player.play()
            
            while player.isPlaying {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            
            player.stop()
            audioPlayer = nil
            
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                startContinuousListening()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Audio playback failed: \(error.localizedDescription)"
                showError = true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                startContinuousListening()
            }
        }
    }
    
    private func speakWithAppleTTS(text: String) async {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Audio session configuration failed: \(error)")
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.speechCompletion = continuation
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            
            speechSynthesizer.speak(utterance)
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        await MainActor.run {
            startContinuousListening()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            speechCompletion?.resume()
            speechCompletion = nil
        }
    }
    
    private func startWaveformMonitoring() {
        waveformTimer?.invalidate()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateWaveform()
            }
        }
    }
    
    private func updateWaveform() {
        if let player = audioPlayer, player.isPlaying {
            player.updateMeters()
            let power = player.averagePower(forChannel: 0)
            let normalizedPower = pow(10, power / 20)
            
            waveformHeights = (0..<20).map { _ in
                let baseHeight: CGFloat = 10
                let maxHeight: CGFloat = 40
                let variation = CGFloat.random(in: 0.7...1.3)
                // Amplify the effect by multiplying normalized power
                let amplifiedPower = min(normalizedPower * 3.0, 1.0)
                let height = baseHeight + (maxHeight - baseHeight) * CGFloat(amplifiedPower) * variation
                return max(baseHeight, min(maxHeight, height))
            }
        } else if speechSynthesizer.isSpeaking {
            waveformHeights = (0..<20).map { _ in
                CGFloat.random(in: 15...35)
            }
        } else {
            waveformHeights = Array(repeating: 10, count: 20)
        }
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    }
    
    private func startSpinner() {
        spinnerTimer?.invalidate()
        spinnerRotation = 0
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.spinnerRotation += 3
                if self.spinnerRotation >= 360 {
                    self.spinnerRotation = 0
                }
            }
        }
    }
    
    private func stopSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        spinnerRotation = 0
    }
}

extension Color {
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
}
