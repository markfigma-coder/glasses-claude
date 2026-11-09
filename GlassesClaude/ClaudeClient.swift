import Foundation
import UIKit

/// Минимальный клиент Claude Messages API (без SDK, чистый URLSession).
struct ClaudeClient {
    struct Turn {
        let role: String   // "user" | "assistant"
        let text: String
    }

    enum ClientError: LocalizedError {
        case noKey
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .noKey:
                return "Не указан ключ Claude API — добавь его в настройках."
            case .http(let code, let body):
                switch code {
                case 401: return "Ключ API не подходит (401). Вставь его заново в настройках."
                case 403: return "Доступ запрещён (403) — скорее всего, запрос идёт без VPN."
                case 429: return "Слишком много запросов (429). Подожди минуту."
                case 529: return "Claude перегружен (529). Попробуй через минуту."
                default:
                    if body.contains("credit balance") { return "На балансе API закончились деньги." }
                    return "Ошибка API \(code): \(body.prefix(200))"
                }
            case .empty:
                return "Пустой ответ от Claude."
            }
        }
    }

    static let systemPrompt = """
    Ты — Claude, голосовой ассистент в умных очках Ray-Ban Meta. Тебя слышат через динамики очков, \
    поэтому отвечай так, как говорят вслух: по-русски, коротко (1–3 предложения), без списков, \
    markdown, эмодзи и ссылок. Числа и сокращения пиши так, чтобы их было удобно произнести. \
    Если к сообщению приложено изображение — это то, что сейчас перед глазами пользователя, \
    снято камерой очков; опирайся на него. Если изображения нет — не делай вид, что видишь. \
    Если не уверен — так и скажи. Пользователь — продуктовый UX/UI-дизайнер: в вопросах про \
    визуал говори как арт-директор — стиль, палитра, типографика, материалы.
    """

    let apiKey: String
    let model: String

    /// Вопрос в рамках разговора (с историей и, при необходимости, кадром).
    func send(history: [Turn], userText: String, image: UIImage?) async throws -> String {
        var messages: [[String: Any]] = history.map { ["role": $0.role, "content": $0.text] }

        var content: [[String: Any]] = []
        if let image, let jpeg = image.resizedForUpload().jpegData(compressionQuality: 0.8) {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": userText])
        messages.append(["role": "user", "content": content])

        return try await post(model: model, system: Self.systemPrompt, messages: messages, maxTokens: 400)
    }

    /// Короткое название темы по первому вопросу и ответу (на быстрой и дешёвой модели).
    func topicTitle(question: String, answer: String) async throws -> String {
        let prompt = "Вопрос: \(question)\nОтвет: \(answer.prefix(400))"
        return try await post(
            model: ClaudeModel.haiku.rawValue,
            system: "Придумай короткое название для этого разговора: 2–4 слова по-русски, с заглавной буквы, без кавычек и точки в конце. Ответь только названием.",
            messages: [["role": "user", "content": prompt]],
            maxTokens: 24
        )
    }

    private func post(model: String, system: String, messages: [[String: Any]], maxTokens: Int) async throws -> String {
        guard !apiKey.isEmpty else { throw ClientError.noKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ClientError.http(status, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else { throw ClientError.empty }

        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.empty }
        return text
    }
}

extension UIImage {
    /// Ужимает до 1280 px по длинной стороне — этого хватает Claude и экономит трафик.
    func resizedForUpload(maxSide: CGFloat = 1280) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
