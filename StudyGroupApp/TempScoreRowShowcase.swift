import SwiftUI

struct TempScoreRowShowcase: View {
    struct Member: Identifiable {
        let id = UUID()
        let name: String
        let score: Double
        let color: Color
    }

    private let members: [Member] = [
        Member(name: "Dimitri", score: 45, color: .green),
        Member(name: "Deanna", score: 33, color: .green),
        Member(name: "D.J.", score: 27, color: .yellow)
    ]

    var body: some View {
        TabView {
            option1
            option2
            option3
            option4
            option5
            option6
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
        OptionPage(title: "Option 1: Split-Color Row") {
            ForEach(members) { member in
                HStack(spacing: 0) {
                    Text(member.name)
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6))

                    Text("\(Int(member.score))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(member.color)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(radius: 2)
            }
        }
    }

    private var option2: some View {
        OptionPage(title: "Option 2: Elevated Score Button") {
            ForEach(members) { member in
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
        }
    }

    private var option3: some View {
        OptionPage(title: "Option 3: Capsule Style") {
            ForEach(members) { member in
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
        }
    }

    private var option4: some View {
        OptionPage(title: "Option 4: Progress Bar Row") {
            ForEach(members) { member in
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
        }
    }

    private var option5: some View {
        OptionPage(title: "Option 5: SF Symbol + Name") {
            ForEach(members) { member in
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(member.color)
                    Text(member.name)
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                    Spacer()
                    Text("\(Int(member.score))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(member.color)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(radius: 2)
            }
        }
    }

    private var option6: some View {
        OptionPage(title: "Option 6: Full Gradient Card") {
            ForEach(members) { member in
                let colors: [Color] = {
                    if member.score >= 50 { return [Color.green.opacity(0.4), .green] }
                    if member.score >= 30 { return [Color.yellow.opacity(0.4), .yellow] }
                    return [Color.white, Color.white]
                }()

                Text(member.name)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
                    .shadow(radius: 2)
            }
        }
    }
}

private struct OptionPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
            content
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    TempScoreRowShowcase()
}

