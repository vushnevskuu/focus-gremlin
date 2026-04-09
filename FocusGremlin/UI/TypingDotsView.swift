import SwiftUI

struct TypingDotsView: View {
    private static let dotGreen = Color(red: 0.12, green: 0.82, blue: 0.32)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Self.dotGreen)
                        .frame(width: 10, height: 10)
                        .opacity(0.4 + 0.55 * (0.5 + 0.5 * sin(t * 5.5 + Double(i) * 0.9)))
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 1)
        }
    }
}
