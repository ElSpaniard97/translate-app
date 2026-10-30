import Foundation
@main struct ModelChecks {
    @MainActor static func main() async {
        let model = TranslatorModel()
        model.add("Hola")
        precondition(model.lines.count == 1)
        let originalID = model.lines[0].id
        var iterator = model.stream(for: .spanishToEnglish).makeAsyncIterator()
        let queuedID = await iterator.next()
        precondition(queuedID == .line(originalID), "Phrases queued before readiness must survive")
        model.update(originalID, translation: "Hello")
        model.direction = .englishToSpanish
        model.add("Good morning")
        precondition(model.lines[0].direction == .spanishToEnglish)
        precondition(model.lines[1].direction == .englishToSpanish)
        let secondID = model.lines[1].id
        model.update(secondID, error: "Test failure")
        model.ready = true
        var reverse = model.stream(for: .englishToSpanish).makeAsyncIterator()
        let reverseID = await reverse.next()
        precondition(reverseID == .line(secondID))
        model.retry(model.lines[1])
        precondition(model.lines[1].error == nil)
        model.update(secondID, translation: "Buenos días")
        precondition(model.exportText.contains("Hello") && model.exportText.contains("Buenos días"))
        model.clear()
        precondition(model.lines.isEmpty && model.canUndo)
        model.undo()
        precondition(model.lines.count == 2 && !model.canUndo)
        print("PASS: queue recovery, phrase direction, retry, export, clear and undo")
    }
    static func awaitValue(_ id: UUID?) -> UUID? { id }
}
