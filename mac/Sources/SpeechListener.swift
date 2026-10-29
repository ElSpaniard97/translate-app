import AVFoundation
import Speech

// Listens to the microphone with Apple's speech recognizer and reports each
// finished phrase. A phrase ends when the speaker pauses briefly.
@MainActor
final class SpeechListener: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isStarting = false
    @Published private(set) var partialText = ""
    @Published private(set) var status = "Press Start listening (or the space bar) and start speaking."

    var onPhrase: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let requestHolder = RequestHolder()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var pauseTimer: Timer?
    // Increases on every restart so late callbacks from an old task are ignored.
    private var generation = 0

    private static let pauseSeconds = 1.2

    func start(localeID: String, languageName: String) async {
        guard !isListening, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        status = "Requesting microphone and speech access…"
        guard await Self.requestPermissions() else {
            status = "Allow Microphone and Speech Recognition for Translator in System Settings → Privacy & Security."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else {
            status = "\(languageName) speech recognition isn't available right now."
            return
        }
        self.recognizer = recognizer

        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = "No microphone is available. Connect an input device and try again."
            return
        }
        Self.installTap(on: audioEngine.inputNode, holder: requestHolder)
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            status = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        isListening = true
        status = recognizer.supportsOnDeviceRecognition
            ? "Listening for \(languageName) (on this Mac)…"
            : "Listening for \(languageName)…"
        startRecognitionTask()
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        commitPhrase()
        generation += 1
        task?.cancel()
        task = nil
        requestHolder.set(nil)
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        status = "Stopped."
    }

    private func startRecognitionTask() {
        guard let recognizer, isListening else { return }
        generation += 1
        task?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        requestHolder.set(request)
        task = Self.makeTask(recognizer: recognizer, request: request, generation: generation, listener: self)
    }

    fileprivate func handle(text: String?, isFinal: Bool, failed: Bool, generation: Int) {
        guard generation == self.generation, isListening else { return }
        if let text {
            partialText = text
            schedulePauseCommit()
        }
        if isFinal {
            commitPhrase()
            startRecognitionTask()
        } else if failed {
            // Usually "no speech detected". Keep what we have and try again shortly.
            commitPhrase()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.generation == generation, self.isListening else { return }
                self.startRecognitionTask()
            }
        }
    }

    private func schedulePauseCommit() {
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: Self.pauseSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                self.commitPhrase()
                self.startRecognitionTask()
            }
        }
    }

    private func commitPhrase() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        let phrase = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        partialText = ""
        if !phrase.isEmpty {
            onPhrase?(phrase)
        }
    }

    // The audio tap and recognition callbacks run on background threads, so they
    // are set up outside the main actor and hop back to it for any UI change.
    private nonisolated static func installTap(on input: AVAudioInputNode, holder: RequestHolder) {
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            holder.append(buffer)
        }
    }

    private nonisolated static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        generation: Int,
        listener: SpeechListener
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                listener.handle(text: text, isFinal: isFinal, failed: failed, generation: generation)
            }
        }
    }

    private nonisolated static func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechAllowed else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}

// Lets the audio thread hand microphone buffers to whichever request is current.
private final class RequestHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request?.endAudio()
        request = newRequest
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }
}
