import AppKit
import AVFoundation
import Combine
import SwiftUI
import Translation
import UniformTypeIdentifiers

enum Direction: String, CaseIterable, Identifiable {
    case spanishToEnglish, englishToSpanish
    var id: String { rawValue }
    var label: String { self == .spanishToEnglish ? "Spanish → English" : "English → Spanish" }
    var spokenLanguageName: String { self == .spanishToEnglish ? "Spanish" : "English" }
    var targetName: String { self == .spanishToEnglish ? "English" : "Spanish" }
    var translationConfig: TranslationSession.Configuration {
        .init(source: Locale.Language(identifier: self == .spanishToEnglish ? "es" : "en"),
              target: Locale.Language(identifier: self == .spanishToEnglish ? "en" : "es"))
    }
}

struct Line: Identifiable {
    let id = UUID()
    let original: String
    let direction: Direction
    let date = Date()
    var translation: String?
    var error: String?
}

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var lines: [Line] = []
    @Published var ready = false
    @Published var preparationError: String?
    @Published var canUndo = false
    let listener = SpeechListener()
    var direction = Direction.spanishToEnglish
    private var cleared: [Line] = []
    private var pending: AsyncStream<UUID>.Continuation?
    private var listenerChanges: AnyCancellable?

    init() {
        listenerChanges = listener.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        listener.onPhrase = { [weak self] phrase in self?.add(phrase) }
    }
    func add(_ original: String) {
        let line = Line(original: original, direction: direction)
        lines.append(line)
        pending?.yield(line.id)
    }
    func stream(for direction: Direction) -> AsyncStream<UUID> {
        pending?.finish()
        let stream = AsyncStream.makeStream(of: UUID.self)
        pending = stream.continuation
        for line in lines where line.direction == direction && line.translation == nil {
            pending?.yield(line.id)
        }
        return stream.stream
    }
    func retry(_ line: Line) {
        guard line.direction == direction, ready,
              let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines[index].error = nil
        pending?.yield(line.id)
    }
    func update(_ id: UUID, translation: String? = nil, error: String? = nil) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].translation = translation
        lines[index].error = error
    }
    func clear() { cleared = lines; lines = []; canUndo = !cleared.isEmpty }
    func undo() {
        lines.insert(contentsOf: cleared, at: 0)
        for line in cleared where line.translation == nil && line.direction == direction { pending?.yield(line.id) }
        cleared = []; canUndo = false
    }
    var exportText: String {
        lines.map { "[\($0.date.formatted(date: .omitted, time: .shortened))] \($0.direction.label)\n\($0.original)\n\($0.translation ?? $0.error ?? "Translation pending")" }.joined(separator: "\n\n")
    }
}

struct TranscriptDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct ContentView: View {
    @StateObject private var model = TranslatorModel()
    @AppStorage("dialect") private var dialect = "es-US"
    @AppStorage("direction") private var direction = Direction.spanishToEnglish
    @AppStorage("transcriptFontSize") private var fontSize = 24.0
    @State private var configuration: TranslationSession.Configuration?
    @State private var mode = "Conversation"
    @State private var draft = ""
    @State private var speaker = AVSpeechSynthesizer()
    @State private var exporting = false
    @State private var exportError: String?
    private var busy: Bool { model.listener.isListening || model.listener.isStarting }
    private var outstanding: Bool { model.lines.contains { $0.direction == direction && $0.translation == nil && $0.error == nil } }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            footer
        }
        .background(Color(red: 0.047, green: 0.065, blue: 0.085))
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.04, green: 0.38, blue: 1))
        .frame(minWidth: 520, minHeight: 720)
        .onAppear { model.direction = direction; configuration = direction.translationConfig }
        .onChange(of: direction) {
            model.direction = direction
            model.ready = false
            model.preparationError = nil
            configuration = direction.translationConfig
        }
        .onDisappear { model.listener.stop() }
        .translationTask(configuration) { session in
            let activeDirection = direction
            model.ready = false
            model.preparationError = nil
            do {
                try await session.prepareTranslation()
                try Task.checkCancellation()
                guard direction == activeDirection else { return }
                model.ready = true
            } catch {
                guard !Task.isCancelled, direction == activeDirection else { return }
                model.preparationError = error.localizedDescription
                return
            }
            for await id in model.stream(for: activeDirection) {
                guard !Task.isCancelled, direction == activeDirection else { return }
                guard let line = model.lines.first(where: { $0.id == id }), line.translation == nil else { continue }
                do {
                    let result = try await session.translate(line.original)
                    try Task.checkCancellation()
                    model.update(id, translation: result.targetText)
                } catch {
                    guard !Task.isCancelled else { return }
                    model.update(id, error: error.localizedDescription)
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: TranscriptDocument(text: model.exportText), contentType: .plainText, defaultFilename: "Translator conversation") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("Couldn’t export conversation", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private let blue = Color(red: 0.04, green: 0.38, blue: 1)
    private let muted = Color(red: 0.70, green: 0.74, blue: 0.80)

    private func swap() {
        direction = direction == .spanishToEnglish ? .englishToSpanish : .spanishToEnglish
    }

    private var header: some View {
        VStack(spacing: 22) {
            HStack(spacing: 18) {
                languageCard(source: true)
                Button(action: swap) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 25, weight: .medium)).foregroundStyle(Color.cyan)
                        .frame(width: 62, height: 62)
                        .background(.black.opacity(0.15), in: Circle())
                        .overlay(Circle().stroke(Color.blue.opacity(0.8), lineWidth: 1.5))
                }.buttonStyle(.plain).disabled(busy || outstanding).help("Swap languages")
                languageCard(source: false)
            }
            HStack(spacing: 0) {
                modeButton("Conversation", icon: "person.2")
                modeButton("Voice", icon: "mic")
                modeButton("Text", icon: "keyboard")
            }
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1.5))
            if let error = model.preparationError {
                HStack {
                    Text("Translation unavailable: \(error)").font(.caption).foregroundStyle(.red)
                    Button("Retry") { configuration?.invalidate() }
                }
            } else if !model.ready {
                HStack { ProgressView().controlSize(.small); Text("Preparing translation…").font(.caption).foregroundStyle(muted) }
            }
        }.padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 16)
    }

    private func languageCard(source: Bool) -> some View {
        let english = source ? direction == .englishToSpanish : direction == .spanishToEnglish
        return VStack(spacing: 10) {
            Text(english ? "🇺🇸" : "🇲🇽").font(.system(size: 36))
            Menu {
                Button("English") { direction = source ? .englishToSpanish : .spanishToEnglish }
                Button("Spanish") { direction = source ? .spanishToEnglish : .englishToSpanish }
            } label: {
                HStack(spacing: 6) { Text(english ? "English" : "Spanish"); Image(systemName: "chevron.down").font(.caption) }
                    .font(.system(size: 20, weight: .medium))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).foregroundStyle(.white).fixedSize().disabled(busy || outstanding)
            if !english {
                Menu {
                    Button("US Spanish") { dialect = "es-US" }
                    Button("Mexican Spanish") { dialect = "es-MX" }
                    Button("Spain Spanish") { dialect = "es-ES" }
                } label: {
                    HStack(spacing: 5) {
                        Text(dialect == "es-MX" ? "Mexican Spanish" : dialect == "es-ES" ? "Spain Spanish" : "US Spanish")
                        Image(systemName: "chevron.down").font(.caption)
                    }.font(.system(size: 16)).foregroundStyle(muted)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(busy)
            } else {
                Text(source ? "Speaking English" : "English translation")
                    .font(.system(size: 15)).foregroundStyle(source ? Color.cyan : muted)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 138)
        .background(LinearGradient(colors: [Color(red: 0.12, green: 0.15, blue: 0.23), Color(red: 0.095, green: 0.12, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1.5))
    }

    private func modeButton(_ title: String, icon: String) -> some View {
        Button {
            if model.listener.isListening { model.listener.stop() }
            mode = title
        } label: {
            Label(title, systemImage: icon).font(.system(size: 18, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(mode == title ? blue : Color.clear, in: RoundedRectangle(cornerRadius: 15))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(model.listener.isStarting)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 15) {
                    if model.lines.isEmpty && model.listener.partialText.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 38)).foregroundStyle(muted.opacity(0.5))
                            Text("Your conversation starts here").font(.system(size: 20, weight: .medium))
                            Text(mode == "Text" ? "Type a message below to translate." : "Tap the microphone and start speaking.").foregroundStyle(muted)
                        }.frame(maxWidth: .infinity).padding(.vertical, 65)
                    }
                    ForEach(model.lines) { line in card(line) }
                    if !model.listener.partialText.isEmpty {
                        HStack { Label(model.listener.partialText, systemImage: "waveform").foregroundStyle(muted); Spacer() }.padding(18)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.horizontal, 28).padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.lines.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: model.listener.partialText) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: model.lines.map { $0.translation }) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func card(_ line: Line) -> some View {
        let right = mode == "Conversation" && line.direction == .spanishToEnglish
        return HStack {
            if right { Spacer(minLength: 64) }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(line.original).font(.system(size: fontSize - 2, weight: .medium)).textSelection(.enabled)
                    if let translation = line.translation {
                        Text(translation).font(.system(size: fontSize - 3)).foregroundStyle(muted).textSelection(.enabled)
                    } else if let error = line.error {
                        Text(error).font(.callout).foregroundStyle(.red)
                        if line.direction == direction { Button("Retry translation") { model.retry(line) }.disabled(!model.ready) }
                    } else { Text("Translating…").foregroundStyle(muted) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let translation = line.translation {
                    Button {
                        let utterance = AVSpeechUtterance(string: translation)
                        utterance.voice = AVSpeechSynthesisVoice(language: line.direction == .spanishToEnglish ? "en-US" : dialect)
                        speaker.stopSpeaking(at: .immediate)
                        speaker.speak(utterance)
                    } label: { Image(systemName: "speaker.wave.2").font(.system(size: 20)).foregroundStyle(muted) }
                        .buttonStyle(.plain).help("Read translation aloud")
                }
            }
            .padding(18)
            .background(LinearGradient(colors: right ? [Color(red: 0.13, green: 0.15, blue: 0.17), Color(red: 0.10, green: 0.12, blue: 0.14)] : [Color(red: 0.13, green: 0.19, blue: 0.28), Color(red: 0.095, green: 0.14, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing), in: BubbleShape(right: right))
            .overlay(BubbleShape(right: right).stroke(right ? .white.opacity(0.09) : Color(red: 0.31, green: 0.41, blue: 0.55).opacity(0.65), lineWidth: 1.5))
            .contextMenu {
                Button("Copy original") { copy(line.original) }
                if let translation = line.translation { Button("Copy translation") { copy(translation) } }
            }
            if !right { Spacer(minLength: 64) }
        }
    }

    private func toggleListening() {
        if model.listener.isListening { model.listener.stop() }
        else { Task { await model.listener.start(localeID: direction == .spanishToEnglish ? dialect : "en-US", languageName: direction.spokenLanguageName) } }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if mode == "Text" {
                HStack {
                    TextField("Type in \(direction.spokenLanguageName)…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).font(.title3).lineLimit(1...4)
                        .onSubmit { submitText() }
                    Button(action: submitText) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(blue) }
                        .buttonStyle(.plain).disabled(!model.ready || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            } else {
                HStack(alignment: .center) {
                    VStack(spacing: 9) {
                        roundButton(icon: model.listener.isListening ? "pause.fill" : "play.fill") { toggleListening() }
                            .disabled(!model.ready || model.listener.isStarting)
                        Text(model.listener.isListening ? "Pause" : "Resume").font(.system(size: 17)).foregroundStyle(muted)
                    }.frame(width: 90)
                    Spacer()
                    VStack(spacing: 13) {
                        Button(action: toggleListening) {
                            Image(systemName: "mic.fill").font(.system(size: 48))
                                .frame(width: 106, height: 106)
                                .background(LinearGradient(colors: [Color(red: 1, green: 0.26, blue: 0.29), Color(red: 0.94, green: 0.16, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 2))
                                .shadow(color: .red.opacity(0.23), radius: 18)
                        }.buttonStyle(.plain).keyboardShortcut(.space, modifiers: []).disabled(!model.ready || model.listener.isStarting)
                        VStack(spacing: 4) {
                            Text(model.listener.isStarting ? "Starting…" : model.listener.isListening ? "Listening…" : "Tap to speak").font(.system(size: 21, weight: .semibold))
                            Text("or press Space").font(.system(size: 16)).foregroundStyle(muted)
                        }
                    }
                    Spacer()
                    VStack(spacing: 9) {
                        roundButton(icon: "trash") { model.clear() }.disabled(model.lines.isEmpty || busy || outstanding)
                        Text("Clear").font(.system(size: 17)).foregroundStyle(muted)
                    }.frame(width: 90)
                }
            }
            if model.listener.isListening || model.listener.isStarting || model.listener.status != "Press Start listening (or the space bar) and start speaking." {
                Text(model.listener.status).font(.caption).foregroundStyle(muted).multilineTextAlignment(.center)
            }
            HStack {
                if model.canUndo { Button("Undo clear") { model.undo() }.buttonStyle(.plain).foregroundStyle(muted) }
                Spacer()
                Menu {
                    Button("Copy conversation") { copy(model.exportText) }
                    Button("Export conversation…") { exporting = true }
                    if mode == "Text" { Button("Clear conversation") { model.clear() }.disabled(outstanding || model.lines.isEmpty) }
                    Divider()
                    Button("Smaller text") { fontSize = max(18, fontSize - 2) }
                    Button("Larger text") { fontSize = min(38, fontSize + 2) }
                } label: { Image(systemName: "ellipsis").foregroundStyle(muted) }.menuStyle(.borderlessButton).fixedSize().help("Conversation options")
            }.font(.caption)
        }.padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 16)
    }

    private func roundButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 27)).foregroundStyle(muted)
                .frame(width: 68, height: 68)
                .background(LinearGradient(colors: [.white.opacity(0.07), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1.5))
        }.buttonStyle(.plain)
    }

    private func submitText() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.ready, !text.isEmpty else { return }
        model.add(text); draft = ""
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

struct BubbleShape: Shape {
    let right: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect.insetBy(dx: 5, dy: 0), cornerRadius: 23)
        let x = right ? rect.maxX - 5 : rect.minX + 5
        let sign: CGFloat = right ? 1 : -1
        path.move(to: CGPoint(x: x, y: rect.maxY - 23))
        path.addQuadCurve(to: CGPoint(x: x + sign * 9, y: rect.maxY - 3), control: CGPoint(x: x, y: rect.maxY - 10))
        path.addQuadCurve(to: CGPoint(x: x - sign * 15, y: rect.maxY - 8), control: CGPoint(x: x + sign * 2, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
