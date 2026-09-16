import SwiftUI

/// The team view: counts, the prose overview, trouble, and open plans.
///
/// Every absence is an explicit statement rather than an empty region. An
/// empty region reads as "nothing to report"; these states mean "nothing was
/// written", "nothing has run yet", or "we could not ask" — different facts
/// that a reader checking on their team needs to tell apart.
struct DebriefView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            Group {
                if let debrief = store.debrief {
                    content(debrief)
                } else if store.debriefNotReady {
                    // 503: the service is up and has nothing yet. Saying
                    // "can't reach point-guard" would send the reader to
                    // debug a connection that is working.
                    ContentUnavailableView(
                        "No debrief yet",
                        systemImage: "clock",
                        description: Text("point-guard is running but has not completed a supervisor tick.")
                    )
                } else if let error = store.debriefError {
                    ContentUnavailableView(
                        "Cannot load debrief",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Debrief")
            .refreshable { await store.refreshDebrief() }
        }
    }

    private func content(_ debrief: Debrief) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                countsRow(debrief.counts)
                narrativeBlock(debrief)
                troubleBlock(debrief)
                plansBlock(debrief)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Counts

    private func countsRow(_ counts: DebriefCounts) -> some View {
        HStack(spacing: 6) {
            countTile("total", counts.total, tint: .secondary)
            countTile("working", counts.working, tint: .green)
            countTile("idle", counts.idle, tint: .secondary)
            countTile("stuck", counts.stuck, tint: .orange)
            countTile("conflicted", counts.conflicted, tint: .red)
        }
    }

    /// Zeroes render as zeroes. Someone checking whether anything is stuck
    /// needs to see "0 stuck" — a hidden tile looks the same as a zero and
    /// answers nothing.
    private func countTile(_ label: String, _ value: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(value == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Narrative

    /// Muted, behind a rule, always attributed — so it never reads as a
    /// measurement. It is model-written prose ABOUT the numbers above.
    @ViewBuilder
    private func narrativeBlock(_ debrief: Debrief) -> some View {
        let state = NarrativeState(debrief: debrief)
        VStack(alignment: .leading, spacing: 4) {
            switch state {
            case .notGenerated:
                Text("No overview generated yet.")
                    .font(.callout).italic()
                    .foregroundStyle(.tertiary)
            case .current(let narrative), .stale(let narrative):
                Text(narrative.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let attribution = state.attribution() {
                    Text(attribution)
                        .font(.caption2)
                        .foregroundStyle(state.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                }
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().frame(width: 2).foregroundStyle(.quaternary)
        }
    }

    // MARK: - Trouble

    @ViewBuilder
    private func troubleBlock(_ debrief: Debrief) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Trouble", count: debrief.trouble.count)
            if debrief.trouble.isEmpty {
                // "Nothing flagged" — NOT "everything is fine". The
                // supervisor reports what it detected; it cannot observe that
                // a session is healthy.
                Text("Nothing flagged.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(debrief.trouble) { trouble in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trouble.kind.replacingOccurrences(of: "_", with: " "))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.statusColor("stuck"))
                        Text(trouble.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private func plansBlock(_ debrief: Debrief) -> some View {
        let health = SourceHealth(status: debrief.sources.plans)
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Plans", count: debrief.plans.count)

            if let warning = health.warning {
                // Empty AND we could not ask. Saying "no plans" here would
                // report a gap in the page as a fact about the world.
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if debrief.plans.isEmpty {
                if health.emptyMeansNone {
                    Text("No open plans.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            } else {
                ForEach(debrief.plans) { plan in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.title)
                            .font(.footnote)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text("\(plan.progress.done)/\(plan.progress.total)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            // The qualifier, never ownership.
                            Text(PlanMatch(rawValue: plan.match).qualifier)
                                .font(.caption2).italic()
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text("(\(count))").font(.caption).foregroundStyle(.tertiary)
        }
    }
}
