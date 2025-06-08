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
        Member(name: "Dimitri", score: 45, color: .green),
        Member(name: "Deanna", score: 33, color: .green),
        Member(name: "D.J.", score: 27, color: .yellow),
        Member(name: "Ron", score: 0, color: .gray),
        Member(name: "Greg", score: 0, color: .gray)
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
            title: "Option 1: Elevated Score Button",
            members: members,
            activity: activity,
            rowBuilder: elevatedRow
        )
    }

    private var option2: some View {
        ScoreboardPage(
            title: "Option 2: Capsule Score",
            members: members,
            activity: activity,
            rowBuilder: capsuleRow
        )
    }

    private var option3: some View {
        ScoreboardPage(
            title: "Option 3: Progress Bar Row",
            members: members,
            activity: activity,
            rowBuilder: progressRow
        )
    }

    private var option4: some View {
        ScoreboardPage(
            title: "Option 4: Real App Layout with Progress",
            members: members,
            activity: activity,
            rowBuilder: inlineProgressRow,
            teamAsTile: true
        )
    }

    private func elevatedRow(_ member: Member) -> some View {
        HStack {
            Text(member.name)
                .font(.system(size: 20, weight: .regular, design: .rounded))
            Spacer()
            Text("\(Int(member.score))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(member.color)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(radius: 2)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    private func capsuleRow(_ member: Member) -> some View {
        HStack {
            Text(member.name)
                .font(.system(size: 20, weight: .regular, design: .rounded))
            Spacer()
            Text("\(Int(member.score))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(member.color)
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    private func progressRow(_ member: Member) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(member.name)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                Spacer()
                Text("\(Int(member.score))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            ProgressView(value: member.score / 100)
                .tint(member.color)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(radius: 2)
    }

    private func inlineProgressRow(_ member: Member) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(member.name)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                Spacer()
                Text("\(Int(member.score))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            ProgressView(value: member.score / 100)
                .tint(member.color)
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
    var teamAsTile: Bool = false

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
                .modifier(TeamContainerModifier(asTile: teamAsTile))

                ActivityCard(items: activity)

                Spacer(minLength: 0)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TeamContainerModifier: ViewModifier {
    let asTile: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if asTile {
            ScoreTile(verticalPadding: 8) { content }
        } else {
            content
                .padding(.horizontal)
        }
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
