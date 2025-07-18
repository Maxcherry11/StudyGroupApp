import SwiftUI


struct TwelveWeekYearView: View {
    @State private var team: [TwelveWeekMember] = [
        .init(name: "Ron B.", goals: [
            .init(title: "Auto", percent: 0.7),
            .init(title: "Fire", percent: 0.6),
            .init(title: "Life", percent: 0.5),
            .init(title: "Training", percent: 0.3)
        ]),
        .init(name: "Deanna", goals: [
            .init(title: "Auto", percent: 0.6),
            .init(title: "Fire", percent: 0.55),
            .init(title: "Life", percent: 0.4),
            .init(title: "Training", percent: 0.45)
        ]),
        .init(name: "D.J.", goals: [
            .init(title: "Auto", percent: 0.5),
            .init(title: "Fire", percent: 0.4),
            .init(title: "Life", percent: 0.6),
            .init(title: "Training", percent: 0.55)
        ]),
        .init(name: "Dimitri", goals: [
            .init(title: "Auto", percent: 0.65),
            .init(title: "Fire", percent: 0.5),
            .init(title: "Life", percent: 0.55),
            .init(title: "Training", percent: 0.4)
        ]),
        .init(name: "Megan", goals: [
            .init(title: "Auto", percent: 0.6),
            .init(title: "Fire", percent: 0.45),
            .init(title: "Life", percent: 0.5),
            .init(title: "Training", percent: 0.35)
        ])
    ].sorted { $0.progress > $1.progress }

    var overallPercent: Double {
        guard !team.isEmpty else { return 0 }
        return team.map { $0.progress * 100 }.reduce(0, +) / Double(team.count)
    }

    var sortedTeam: [TwelveWeekMember] {
        team.sorted { $0.progress > $1.progress }
    }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 60/255, green: 90/255, blue: 140/255))
                    .shadow(color: .black.opacity(0.3), radius: 12)

                VStack(spacing: 75) {
                    Text("12 Week Year")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)

                    GaugeView(percentage: overallPercent)
                        .frame(height: 140)

                    Text("On-Time % for Team")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(team.enumerated().sorted { $0.element.progress > $1.element.progress }), id: \.element.id) { index, member in
                            NavigationLink(destination: CardView(member: $team[index])) {
                                HStack {
                                    Text(member.name)
                                        .font(.system(size: 26, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 100, alignment: .leading)
                                        .padding(.trailing, 40)

                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.white.opacity(0.12))
                                            .frame(height: 15)
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.blue)
                                            .frame(width: CGFloat(member.progress) * 200, height: 15)
                                    }
                                    .frame(width: 200, height: 10)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 0)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
        }
    }
}

struct GaugeView: View {
    let percentage: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ArcShape(startAngle: .degrees(180), endAngle: .degrees(0))
                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 25, lineCap: .round))

                ArcShape(startAngle: .degrees(180), endAngle: .degrees(180 + (percentage / 100 * 180)))
                    .stroke(AngularGradient(
                        gradient: Gradient(colors: [.red, .orange, .green]),
                        center: .center,
                        startAngle: .degrees(180),
                        endAngle: .degrees(360)
                    ), style: StrokeStyle(lineWidth: 25, lineCap: .round))

                Text("\(Int(percentage))%")
                    .font(.system(size: 44, weight: .bold))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .offset(y: 20)
            }
        }
    }
}

struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2.4,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

struct TwelveWeekYearView_Previews: PreviewProvider {
    static var previews: some View {
        TwelveWeekYearView()
            .preferredColorScheme(.dark)
    }
}
    
