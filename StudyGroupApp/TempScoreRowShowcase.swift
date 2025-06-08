import SwiftUI

struct TempScoreRowShowcase: View {
    struct Member: Identifiable {
        let id = UUID()
        let name: String
        let score: Double
        let color: Color
    }

    struct ActivityItem: Identifiable {
        let id = UUID()
        let name: String
        let pending: Int
        let projected: Double
    }

    private let members: [Member] = [
        Member(name: "D.J.",    score: 33, color: .green),
        Member(name: "Deanna",  score: 33, color: .green),
        Member(name: "Dimitri", score: 33, color: .green),
        Member(name: "Greg",    score: 18, color: .yellow),
        Member(name: "Ron",     score: 15, color: .gray)
    ]

    private let activity: [ActivityItem] = [
        ActivityItem(name: "Dimitri", pending: 2, projected: 1500),
        ActivityItem(name: "Deanna", pending: 3, projected: 800),
        ActivityItem(name: "D.J.", pending: 7, projected: 600),
        ActivityItem(name: "Ron", pending: 0, projected: 0),
        ActivityItem(name: "Greg", pending: 0, projected: 0)
    ]

    var body: some View {
        TabView {
            option1
            option2
            option3
            option4
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var option1: some View {
        ScoreboardPage(
            title: "Option 1: Mini Meter",
            members: members,
            activity: activity,
            rowBuilder: miniMeterRow
        )
    }

    private var option2: some View {
        ScoreboardPage(
            title: "Option 2: Color Fill Cell",
            members: members,
            activity: activity,
            rowBuilder: colorFillRow
        )
    }

    private var option3: some View {
        ScoreboardPage(
            title: "Option 3: Capsule Progress",
            members: members,
            activity: activity,
            rowBuilder: capsuleProgressRow
        )
    }

    private var option4: some View {
        ScoreboardPage(
            title: "Option 4: Glow Bar",
            members: members,
            activity: activity,
            rowBuilder: glowProgressRow
        )
    }

    private func miniMeterRow(_ member: Member) -> some View {
        let filled = Int(round(member.score / 10))
        return HStack(spacing: 8) {
            Text(member.name)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .frame(width: 100, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(0..<10) { index in
                    Circle()
                        .fill(index < filled ? member.color : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(Int(member.score))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func colorFillRow(_ member: Member) -> some View {
        let background: Color = {
            if member.score >= 40 { return Color.green.opacity(0.2) }
            if member.score >= 30 { return Color.yellow.opacity(0.2) }
            return Color.gray.opacity(0.2)
        }()

        return HStack(spacing: 8) {
            Text(member.name)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .frame(width: 100, alignment: .leading)
            Spacer()
            Text("\(Int(member.score))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(background)
        .cornerRadius(12)
    }

    private func capsuleProgressRow(_ member: Member) -> some View {
        HStack(spacing: 8) {
            Text(member.name)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .frame(width: 100, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(member.color)
                        .frame(width: geo.size.width * member.score / 100)
                }
            }
            .frame(height: 8)
            .frame(maxWidth: .infinity)

            Text("\(Int(member.score))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func glowProgressRow(_ member: Member) -> some View {
        HStack(spacing: 8) {
            Text(member.name)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .frame(width: 100, alignment: .leading)

            ProgressView(value: member.score / 100)
                .tint(member.color)
                .frame(height: 6)
                .frame(maxWidth: .infinity)
                .clipShape(Capsule())
                .shadow(color: member.color.opacity(0.4), radius: 6)

            Text("\(Int(member.score))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

private struct ScoreBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(color)
            .cornerRadius(8)
    }
}

private struct ScoreTile<Content: View>: View {
    var verticalPadding: CGFloat = 16
    var horizontalPadding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(radius: 4)

            content()
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, horizontalPadding)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OnTimeCard: View {
    let onTime: Double
    let travel: Double

    var body: some View {
        ScoreTile {
            HStack(alignment: .center) {
                VStack(spacing: 2) {
                    Text("Honor")
                        .font(.system(size: 17, weight: .semibold))
                    ScoreBadge(text: String(format: "%.1f", onTime), color: .yellow)
                }

                Spacer()

                Text("On Time")
                    .font(.system(size: 24, weight: .bold))

                Spacer()

                VStack(spacing: 2) {
                    Text("Travel")
                        .font(.system(size: 17, weight: .semibold))
                    ScoreBadge(text: String(format: "%.1f", travel), color: .green)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ScoreboardPage<RowContent: View>: View {
    let title: String
    let members: [TempScoreRowShowcase.Member]
    let activity: [TempScoreRowShowcase.ActivityItem]
    let rowBuilder: (TempScoreRowShowcase.Member) -> RowContent

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 8) {
                    Text("Life Scoreboard")
                        .font(.system(size: 34, weight: .bold))
                    Text("3 Weeks Remaining")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .cornerRadius(20)
                    Text("Second Year")
                        .font(.system(size: 15, weight: .regular))
                }

                OnTimeCard(onTime: 17.7, travel: 31.0)

                Group {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Team")
                            .font(.system(size: 20, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .center)

                        ForEach(members) { member in
                            rowBuilder(member)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .modifier(TeamContainerModifier())

                ActivityCard(items: activity)

                Spacer(minLength: 0)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TeamContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 4)
            .padding()
    }
}

private struct ActivityCard: View {
    let items: [TempScoreRowShowcase.ActivityItem]

    var body: some View {
        ScoreTile(verticalPadding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Activity")
                    .font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 6) {
                    Text("Name")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Pending")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 70, alignment: .center)
                    Text("Projected")
                        .font(.system(size: 16, weight: .bold))
                        .frame(minWidth: 110, alignment: .trailing)
                }

                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 20, weight: .regular, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(item.pending)")
                            .font(.system(size: 15, weight: .regular))
                            .frame(width: 70, alignment: .center)
                            .monospacedDigit()
                        Text(item.projected, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.green)
                            .frame(minWidth: 110, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    TempScoreRowShowcase()
}
