import SwiftUI

struct TwelveWeekYearView: View {
    @StateObject private var viewModel = TwelveWeekYearViewModel()
    @ObservedObject private var userManager = UserManager.shared
    @State private var selectedMember: TwelveWeekMember? = nil

    var overallPercent: Double {
        guard !viewModel.members.isEmpty else { return 0 }
        return viewModel.members.map { $0.progress * 100 }.reduce(0, +) / Double(viewModel.members.count)
    }

    var sortedTeam: [TwelveWeekMember] {
        viewModel.members.sorted { $0.progress > $1.progress }
    }

    var body: some View {
        Group {
                ZStack {
                    GeometryReader { _ in
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
                                    ForEach(sortedTeam) { member in
                                        let binding = Binding<TwelveWeekMember>(
                                            get: {
                                                viewModel.members.first(where: { $0.id == member.id }) ?? member
                                            },
                                            set: { updated in
                                                if let i = viewModel.members.firstIndex(where: { $0.id == updated.id }) {
                                                    viewModel.members[i] = updated
                                                }
                                            }
                                        )
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
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedMember = member
                                        }
                                    }
                                }
                                .padding(.horizontal, 0)
                            }
                            .padding(16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                    }

                .fullScreenCover(item: $selectedMember) { member in
                    NavigationView {
                        let binding = Binding<TwelveWeekMember>(
                            get: {
                                viewModel.members.first(where: { $0.id == member.id }) ?? member
                            },
                            set: { updated in
                                if let i = viewModel.members.firstIndex(where: { $0.id == updated.id }) {
                                    viewModel.members[i] = updated
                                }
                            }
                        )
                        CardView(member: binding)
                            .onDisappear {
                                viewModel.saveMember(binding.wrappedValue)
                            }
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button("Back") {
                                        selectedMember = nil
                                    }
                                }
                            }
                    }
                }
        }
        .onAppear {
            viewModel.fetchMembersFromCloud()
        }
        .onChange(of: userManager.userList) { _ in
            viewModel.fetchMembersFromCloud()
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
