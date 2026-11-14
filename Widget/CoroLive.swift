import SwiftUI
import WidgetKit
import ActivityKit

@main
struct CoroWidgetBundle: WidgetBundle {
    var body: some Widget { CoroLiveActivity() }
}

struct CoroLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoroAttributes.self) { context in
            LyricsCard(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.isDemo ? "DEMO" : "Coro", systemImage: "music.note")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.isStale ? "Esperando a Spotify…" : context.state.line)
                            .font(.headline).lineLimit(2)
                        if !context.isStale {
                            Text(context.state.nextLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "music.note").foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.isStale ? "…" : (context.state.isDemo ? "DEMO" : "Coro")).font(.caption2)
            } minimal: {
                Image(systemName: "music.note").foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

struct LyricsCard: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<CoroAttributes>
    private let coral = Color(red: 1, green: 0.52, blue: 0.39)

    var body: some View {
        VStack(alignment: .leading, spacing: family == .small ? 5 : 8) {
            HStack(spacing: 5) {
                Image(systemName: "music.note").foregroundStyle(coral)
                Text(context.state.isDemo ? "DEMO" : context.state.title).lineLimit(1)
                Spacer(minLength: 0)
                if !context.state.isPlaying { Image(systemName: "pause.fill") }
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
            Text(context.isStale ? "Esperando a Spotify…" : context.state.line)
                .font(family == .small ? .system(size: 18, weight: .bold, design: .rounded) : .title3.weight(.semibold))
                .foregroundStyle(coral)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !context.isStale, !context.state.nextLine.isEmpty {
                Text(context.state.nextLine)
                    .font(family == .small ? .caption2 : .subheadline)
                    .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            if family != .small, !context.state.notice.isEmpty {
                Text(context.state.notice).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
        }
        .padding(family == .small ? 9 : 16)
    }
}
