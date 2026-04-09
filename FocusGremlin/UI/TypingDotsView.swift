import SwiftUI

struct TypingDotsView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.55 * (0.5 + 0.5 * sin(t * 5.5 + Double(i) * 0.9)))
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
