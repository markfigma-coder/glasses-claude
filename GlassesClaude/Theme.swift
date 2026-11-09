import SwiftUI

// MARK: Цвета и фон

enum Theme {
    static let ink = Color.white
    static let inkSecondary = Color.white.opacity(0.75)
    static let inkTertiary = Color.white.opacity(0.55)
    static let deepBlue = Color(red: 0.13, green: 0.33, blue: 0.92)
    static let glassFill = Color.white.opacity(0.16)
    static let glassStroke = Color.white.opacity(0.35)
}

/// Голубой градиент как в референсе: светлый верх, насыщенная середина, светлый низ.
struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.66, green: 0.84, blue: 1.00),
                    Color(red: 0.30, green: 0.56, blue: 0.99),
                    Color(red: 0.19, green: 0.42, blue: 0.96),
                    Color(red: 0.56, green: 0.77, blue: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.white.opacity(0.30), .clear],
                center: UnitPoint(x: 0.5, y: 0.48),
                startRadius: 20,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: Стекло

struct GlassBackground: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.glassStroke, lineWidth: 1)
            )
    }
}

extension View {
    func glass(radius: CGFloat = 22) -> some View {
        modifier(GlassBackground(radius: radius))
    }
}

/// Круглая стеклянная кнопка 44×44 для верхней панели.
struct GlassIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .glass(radius: 22)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Сфера

enum OrbMood: Equatable {
    case idle, listening, thinking, speaking, error
}

/// «Живая» сфера: лепестки света вращаются и пульсируют в зависимости от состояния.
struct OrbView: View {
    var mood: OrbMood

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [coreLight, coreDark],
                                center: .center,
                                startRadius: 0,
                                endRadius: s / 2
                            )
                        )
                    ForEach(0..<6, id: \.self) { i in
                        Ellipse()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.9), Color.white.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: s * 0.38, height: s * 0.64)
                            .offset(y: -s * 0.17)
                            .rotationEffect(.degrees(Double(i) * 60 + t * speed * 40))
                            .opacity(0.5)
                            .blendMode(.plusLighter)
                    }
                    .blur(radius: s * 0.015)
                }
                .frame(width: s, height: s)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: max(2, s * 0.012)))
                .shadow(color: glow, radius: s * 0.14)
                .scaleEffect(pulse(t))
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var speed: Double {
        switch mood {
        case .idle: return 0.25
        case .listening: return 0.6
        case .thinking: return 1.8
        case .speaking: return 1.0
        case .error: return 0.12
        }
    }

    private func pulse(_ t: Double) -> Double {
        switch mood {
        case .listening: return 1 + 0.025 * sin(t * 3)
        case .thinking: return 1 + 0.02 * sin(t * 6)
        case .speaking: return 1 + 0.045 * sin(t * 8)
        default: return 1
        }
    }

    private var coreLight: Color {
        mood == .error ? Color(red: 1.0, green: 0.55, blue: 0.5) : Color(red: 0.42, green: 0.62, blue: 1.0)
    }

    private var coreDark: Color {
        mood == .error ? Color(red: 0.85, green: 0.25, blue: 0.3) : Color(red: 0.14, green: 0.34, blue: 0.95)
    }

    private var glow: Color {
        mood == .error ? Color.red.opacity(0.45) : Color.white.opacity(0.65)
    }
}

// MARK: Русские формы и даты

enum RU {
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    static func messages(_ n: Int) -> String {
        "\(n) \(plural(n, "сообщение", "сообщения", "сообщений"))"
    }

    static func topics(_ n: Int) -> String {
        "\(n) \(plural(n, "тема", "темы", "тем"))"
    }

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "только что" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
