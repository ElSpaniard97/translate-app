import Combine
import SwiftUI
import Translation

struct Line: Identifiable {
    let id = UUID()
    let spanish: String
    var english: String?
}

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var lines: [Line] = []
    let listener = SpeechListener()

    // Finished phrases waiting to be translated. The translation task below reads from it.
    let pending: AsyncStream<Line.ID>
    private let pendingContinuation: AsyncStream<Line.ID>.Continuation
    private var listenerChanges: AnyCancellable?

    init() {
        let stream = AsyncStream.makeStream(of: Line.ID.self)
        pending = stream.stream
        pendingContinuation = stream.continuation
        listenerChanges = listener.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        listener.onPhrase = { [weak self] phrase in
            self?.add(phrase)
        }
    }

    func add(_ spanish: String) {
        let line = Line(spanish: spanish)
        lines.append(line)
        pendingContinuation.yield(line.id)
    }

    func spanish(for id: Line.ID) -> String? {
        lines.first { $0.id == id }?.spanish
    }

    func setEnglish(_ english: String, for id: Line.ID) {
        if let index = lines.firstIndex(where: { $0.id == id }) {
            lines[index].english = english
        }
    }

    func clear() {
        lines.removeAll()
    }
}

struct ContentView: View {
    @StateObject private var model = TranslatorModel()
    @AppStorage("dialect") private var dialect = "es-US"

    private let translationConfig = TranslationSession.Configuration(
        source: Locale.Language(identifier: "es"),
        target: Locale.Language(identifier: "en")
    )

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            transcript
        }
        .frame(minWidth: 380, minHeight: 400)
        // Apple's on-device translator. macOS asks once to download the Spanish
        // language pack if it isn't installed yet.
        .translationTask(translationConfig) { session in
            try? await session.prepareTranslation()
            for await id in model.pending {
                guard let spanish = await model.spanish(for: id) else { continue }
                do {
                    let response = try await session.translate(spanish)
                    await model.setEnglish(response.targetText, for: id)
                } catch {
                    await model.setEnglish("(Could not translate: \(error.localizedDescription))", for: id)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Spanish", selection: $dialect) {
                    Text("Spanish (US)").tag("es-US")
                    Text("Spanish (Mexico)").tag("es-MX")
                    Text("Spanish (Spain)").tag("es-ES")
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                .disabled(model.listener.isListening)

                Button(model.listener.isListening ? "Stop" : "Start listening") {
                    if model.listener.isListening {
                        model.listener.stop()
                    } else {
                        Task { await model.listener.start(localeID: dialect) }
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
                            Text(line.english ?? "Translating…")
                                .font(.title2.weight(.semibold))
                            Text(line.spanish)
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
