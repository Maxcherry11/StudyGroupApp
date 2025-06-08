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
        Member(name: "D.J.", score: 27, color: .yellow)
    ]

    private let activity: [ActivityItem] = [
        ActivityItem(name: "Dimitri", pending: 2, projected: 1500),
        ActivityItem(name: "Deanna", pending: 3, projected: 800),
        ActivityItem(name: "D.J.", pending: 1, projected: 600)
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
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.3), Color.gray]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
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
            title: "Option 4: Full Gradient Row",
            members: members,
            activity: activity,
            rowBuilder: gradientRow
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

    private func gradientRow(_ member: Member) -> some View {
        let yellow = Color(red: 1.0, green: 0.85, blue: 0.0)
        let colors: [Color] = {
            if member.score >= 40 { return [Color.green.opacity(0.4), .green] }
            if member.score >= 25 { return [yellow.opacity(0.4), yellow] }
            return [Color.white, Color.white]
        }()

        return HStack {
            Text(member.name)
                .font(.system(size: 20, weight: .regular, design: .rounded))
            Spacer()
            Text("\(Int(member.score))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        )
        .cornerRadius(16)
        .shadow(radius: 2)
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Team")
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .center)

                    ForEach(members) { member in
                        rowBuilder(member)
                    }
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity")
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Text("Name")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Pending")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 70)
                        Text("Projected")
                            .font(.system(size: 16, weight: .bold))
                            .frame(minWidth: 110, alignment: .trailing)
                    }

                    ForEach(activity) { item in
                        HStack {
                            Text(item.name)
                                .font(.system(size: 20, weight: .regular, design: .rounded))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(item.pending)")
                                .font(.system(size: 15, weight: .regular))
                                .frame(width: 70)
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
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(radius: 2)

                Spacer(minLength: 0)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    TempScoreRowShowcase()
}
