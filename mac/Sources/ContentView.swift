import Combine
import SwiftUI
import Translation

enum Direction: String, CaseIterable, Identifiable {
    case spanishToEnglish
    case englishToSpanish

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spanishToEnglish: "Spanish → English"
        case .englishToSpanish: "English → Spanish"
        }
    }

    var spokenLanguageName: String {
        switch self {
        case .spanishToEnglish: "Spanish"
        case .englishToSpanish: "English"
        }
    }

    var translationConfig: TranslationSession.Configuration {
        let spanish = Locale.Language(identifier: "es")
        let english = Locale.Language(identifier: "en")
        switch self {
        case .spanishToEnglish: return .init(source: spanish, target: english)
        case .englishToSpanish: return .init(source: english, target: spanish)
        }
    }
}

struct Line: Identifiable {
    let id = UUID()
    let original: String
    var translation: String?
}

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var lines: [Line] = []
    let listener = SpeechListener()

    // Finished phrases waiting to be translated. The translation task below reads
    // from it, and gets a fresh stream each time the direction changes.
    private var pendingContinuation: AsyncStream<Line.ID>.Continuation?
    private var listenerChanges: AnyCancellable?

    init() {
        listenerChanges = listener.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        listener.onPhrase = { [weak self] phrase in
            self?.add(phrase)
        }
    }

    func newPendingStream() -> AsyncStream<Line.ID> {
        pendingContinuation?.finish()
        let stream = AsyncStream.makeStream(of: Line.ID.self)
        pendingContinuation = stream.continuation
        return stream.stream
    }

    func add(_ original: String) {
        let line = Line(original: original)
        lines.append(line)
        pendingContinuation?.yield(line.id)
    }

    func original(for id: Line.ID) -> String? {
        lines.first { $0.id == id }?.original
    }

    func setTranslation(_ translation: String, for id: Line.ID) {
        if let index = lines.firstIndex(where: { $0.id == id }) {
            lines[index].translation = translation
        }
    }

    func clear() {
        lines.removeAll()
    }
}

struct ContentView: View {
    @StateObject private var model = TranslatorModel()
    @AppStorage("dialect") private var dialect = "es-US"
    @AppStorage("direction") private var direction = Direction.spanishToEnglish

    private var speechLocale: String {
        direction == .spanishToEnglish ? dialect : "en-US"
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            transcript
        }
        .frame(minWidth: 420, minHeight: 400)
        // Apple's on-device translator. macOS asks once to download a language
        // pack if it isn't installed yet. This restarts when the direction changes.
        .translationTask(direction.translationConfig) { session in
            let pending = await model.newPendingStream()
            try? await session.prepareTranslation()
            for await id in pending {
                guard let original = await model.original(for: id) else { continue }
                do {
                    let response = try await session.translate(original)
                    await model.setTranslation(response.targetText, for: id)
                } catch {
                    await model.setTranslation("(Could not translate: \(error.localizedDescription))", for: id)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Direction", selection: $direction) {
                ForEach(Direction.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.listener.isListening)

            HStack {
                Picker("Spanish", selection: $dialect) {
                    Text("Spanish (US)").tag("es-US")
                    Text("Spanish (Mexico)").tag("es-MX")
                    Text("Spanish (Spain)").tag("es-ES")
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                .disabled(model.listener.isListening || direction == .englishToSpanish)

                Button(model.listener.isListening ? "Stop" : "Start listening") {
                    if model.listener.isListening {
                        model.listener.stop()
                    } else {
                        Task { await model.listener.start(localeID: speechLocale, languageName: direction.spokenLanguageName) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.listener.isListening ? .red : .accentColor)
                .keyboardShortcut(.space, modifiers: [])

                Button("Clear") { model.clear() }
            }
            Text(model.listener.status)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.lines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.translation ?? "Translating…")
                                .font(.title2.weight(.semibold))
                            Text(line.original)
                                .foregroundStyle(.secondary)
                        }
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if !model.listener.partialText.isEmpty {
                        Text(model.listener.partialText)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .onChange(of: model.lines.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: model.listener.partialText) {
                proxy.scrollTo("bottom")
            }
        }
    }
}
