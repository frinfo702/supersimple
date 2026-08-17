import SupersimpleCore
import SwiftUI

/// Status strip under the editor: counts, last-updated time, and the current note's tags.
struct BottomBarView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            stats
            Spacer(minLength: 12)
            tags
        }
        .padding(.horizontal, 18)
        .frame(height: AppTheme.Metric.bottomBarHeight)
        .background(Color(nsColor: AppTheme.Color.sidebarBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.hairline)
                .frame(height: AppTheme.Metric.hairlineWidth)
        }
        .accessibilityIdentifier("bottom-bar")
        .accessibilityElement(children: .contain)
    }

    private var stats: some View {
        HStack(spacing: 8) {
            Text(wordLabel)
            Text("·")
                .foregroundStyle(Color.supersimpleMuted.opacity(0.6))
            Text(characterLabel)
            if let updated = updatedLabel {
                Text("·")
                    .foregroundStyle(Color.supersimpleMuted.opacity(0.6))
                Text(updated)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.supersimpleMuted)
        .lineLimit(1)
        .accessibilityIdentifier("bottom-bar-stats")
        .accessibilityLabel(accessibilityStats)
    }

    @ViewBuilder
    private var tags: some View {
        if let note = model.currentNote(), !note.tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(note.tags.sorted(), id: \.self) { tag in
                    Button {
                        model.selectTag(tag)
                    } label: {
                        Text("#\(tag.name)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(
                                model.selectedTag == tag
                                    ? Color.supersimpleAccent : Color.supersimpleMuted
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tag #\(tag.name)")
                }
            }
            .lineLimit(1)
        }
    }

    private var wordLabel: String {
        let count = NoteStats.wordCount(model.currentBody)
        return count == 1 ? "1 word" : "\(count) words"
    }

    private var characterLabel: String {
        let count = NoteStats.characterCount(model.currentBody)
        return count == 1 ? "1 character" : "\(count) characters"
    }

    private var updatedLabel: String? {
        guard let note = model.currentNote() else { return nil }
        return "Updated \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var accessibilityStats: String {
        [wordLabel, characterLabel, updatedLabel].compactMap { $0 }.joined(separator: ", ")
    }
}
