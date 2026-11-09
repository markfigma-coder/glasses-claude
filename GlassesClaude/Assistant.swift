import Foundation
import UIKit

/// Связывает всё вместе: фраза или текст → Claude → ответ (голосом в очки, если идёт голосовая сессия).
@MainActor
final class Assistant: ObservableObject {
    enum Status: Equatable {
        case off, starting, listening, thinking, speaking
        case error(String)
    }

    @Published private(set) var status: Status = .off
    /// Идёт голосовая сессия с очками (микрофон слушает).
    @Published private(set) var isRunning = false
    /// Claude сейчас готовит ответ — новые вопросы пока не принимаем.
    @Published private(set) var isBusy = false
    @Published private(set) var lastQuestion = ""
    @Published private(set) var lastAnswer = ""
    /// Короткая подсказка на главном экране (исчезает сама).
    @Published private(set) var hint: String?
    /// Следующая фраза будет принята без «Клод» (тап по сфере).
    @Published var forceNextUtterance = false

    let glasses = GlassesManager()
    let voice = VoiceEngine()
    let library: LibraryStore
    private let settings = AppSettings.shared
    private var hintTask: Task<Void, Never>?

    /// Слова, по которым понятно, что нужен кадр с камеры.
    private let visualCues = ["посмотри", "смотри", "что это", "что я вижу", "видишь", "что передо мной",
                              "опиши", "прочитай", "прочти", "переведи", "сфоткай", "сними", "кадр",
                              "какой шрифт", "какой цвет", "какого цвета", "что за", "палитр", "референс"]
    /// Как распознаватель слышит «Клод» — ловим все частые варианты.
    private let wakeWords = ["клод", "клот", "клоуд", "клауд", "глод", "claude", "cloud"]

    /// После такой паузы разговор начинается заново, в новой теме.
    private let topicIdleInterval: TimeInterval = 30 * 60

    init(library: LibraryStore) {
        self.library = library
        voice.onUtterance = { [weak self] text in self?.handle(utterance: text) }
    }

    // MARK: Голосовая сессия

    func start() async {
        guard !isRunning, status != .starting else { return }
        status = .starting
        do {
            guard await voice.requestPermissions() else { throw AssistantError.permissions }
            if GlassesManager.cameraEnabled {
                try await glasses.ensureCameraPermission()
            }
            // Порядок важен: сессия с очками → микрофон (HFP) → поток камеры
            try await glasses.prepareSession()
            try await voice.startAudio(useGlassesMic: settings.useGlassesMic)
            glasses.startStream()
            isRunning = true
            voice.startListening()
            status = isBusy ? .thinking : .listening
            if settings.useGlassesMic && !voice.glassesMicActive {
                showHint("Микрофон очков не подключился — слушаю через iPhone")
            }
        } catch {
            stopVoice()
            status = .error(error.localizedDescription)
        }
    }

    func stop() {
        stopVoice()
        status = isBusy ? .thinking : .off
    }

    private func stopVoice() {
        voice.stopAudio()
        glasses.stop()
        isRunning = false
        forceNextUtterance = false
    }

    /// Тап по сфере во время прослушивания: следующая фраза уйдёт без «Клод».
    func listenWithoutWakeWord() {
        guard isRunning else { return }
        forceNextUtterance = true
        showHint("Говори — отправлю следующую фразу целиком")
    }

    func interrupt() {
        voice.stopSpeaking()
    }

    // MARK: Входящие фразы и текст

    private func handle(utterance raw: String) {
        guard !isBusy else { return }
        var question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.count >= 2 else { return }

        if settings.requireWakeWord && !forceNextUtterance {
            let found = wakeWords.compactMap {
                question.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])
            }.first
            guard let range = found else {
                showHint("Не услышал «Клод» — пропустил: «\(question)»")
                return
            }
            // Отрезаем «Клод» вместе с окончанием («Клоду», «Клода») и запятой
            question = String(question[range.upperBound...].drop(while: { $0.isLetter }))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?—-"))
            if question.isEmpty { question = "Привет!" }
        }
        forceNextUtterance = false

        var needsImage: Bool
        switch settings.imageMode {
        case .always: needsImage = true
        case .never: needsImage = false
        case .auto:
            let lower = question.lowercased()
            needsImage = visualCues.contains { lower.contains($0) }
        }
        if !GlassesManager.cameraEnabled { needsImage = false }

        submit(question, source: .voice, withImage: needsImage)
    }

    /// Текстовое сообщение из приложения. Возвращает id темы, куда оно ушло.
    @discardableResult
    func sendText(_ text: String, inTopic topicId: UUID? = nil) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return nil }
        if let topicId { library.currentTopicId = topicId }
        return submit(trimmed, source: .text, withImage: false)
    }

    @discardableResult
    private func submit(_ question: String, source: ChatMessage.Source, withImage: Bool) -> UUID {
        isBusy = true
        status = .thinking
        lastQuestion = question
        library.splitIfIdle(after: topicIdleInterval)
        let history = library.apiHistory()
        let topicId = library.appendToCurrent(ChatMessage(role: .user, text: question, source: source))
        Task { await request(question, topicId: topicId, history: history, source: source, withImage: withImage) }
        return topicId
    }

    private func request(_ question: String, topicId: UUID, history: [ClaudeClient.Turn],
                         source: ChatMessage.Source, withImage: Bool) async {
        let image = withImage ? await glasses.snapshot() : nil
        let prompt = (withImage && image == nil)
            ? "\(question)\n[Системная пометка: камера очков сейчас недоступна, изображения нет.]"
            : question
        let client = ClaudeClient(apiKey: settings.apiKey, model: settings.model.rawValue)

        do {
            let answer = try await client.send(history: history, userText: prompt, image: image)
            library.append(ChatMessage(role: .assistant, text: answer, source: source), to: topicId)
            lastAnswer = answer
            nameTopicIfNeeded(topicId, question: question, answer: answer, client: client)
            if isRunning {
                status = .speaking
                voice.speak(answer, rate: settings.speechRate)
                await waitUntilSpoken()
            }
        } catch {
            let message = error.localizedDescription
            library.append(ChatMessage(role: .assistant, text: message, source: source, isError: true), to: topicId)
            lastAnswer = message
            if isRunning {
                status = .speaking
                voice.speak("Не получилось получить ответ. Подробности в приложении.", rate: settings.speechRate)
                await waitUntilSpoken()
            }
        }

        isBusy = false
        if case .error = status { return }
        status = isRunning ? .listening : .off
    }

    /// После первого ответа в теме просим Claude придумать ей короткое название.
    private func nameTopicIfNeeded(_ topicId: UUID, question: String, answer: String, client: ClaudeClient) {
        guard let topic = library.topic(topicId), !topic.titleIsManual,
              topic.messages.filter({ !$0.isError }).count == 2 else { return }
        Task {
            if let title = try? await client.topicTitle(question: question, answer: answer) {
                library.setAutoTitle(topicId, title)
            }
        }
    }

    private func waitUntilSpoken() async {
        while voice.isSpeaking {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func showHint(_ text: String) {
        hint = text
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hint = nil
        }
    }
}

enum AssistantError: LocalizedError {
    case permissions

    var errorDescription: String? {
        "Дай доступ к микрофону и распознаванию речи: Настройки iOS → Клод в очках."
    }
}
