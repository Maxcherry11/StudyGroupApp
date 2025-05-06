import SwiftUI

struct UserSelectorView: View {
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @State private var navigateToWin = false

    let users = ["D.J.", "Ron", "Deanna", "Dimitri"]

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Who Are You?")
                    .font(.largeTitle.bold())
                    .padding(.top, 60)
                ForEach(users, id: \.self) { name in
                    Button(action: {
                        selectedUserName = name
                        navigateToWin = true
                    }) {
                        Text(name)
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                }
                NavigationLink(
                    destination: WinTheDayView(),
                    isActive: $navigateToWin
                ) {
                    EmptyView()
                }
                Spacer()
            }
            .padding(.horizontal)
            .navigationBarHidden(true)
        }
    }
}

struct DashboardView: View {
    var body: some View {
        Text("Dashboard")
            .font(.largeTitle)
            .padding()
    }
}

struct SettingsView: View {
    var body: some View {
        Text("Settings")
            .font(.largeTitle)
            .padding()
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct WinTheDayView: View {
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @AppStorage("goalText") private var goalText: String = "Your Goal"
    @Environment(\.presentationMode) var presentationMode

    @State private var team: [TeamMember] = [
        TeamMember(name: "D.J.", quotesToday: 10, salesWTD: 2, salesMTD: 5, quotesGoal: 10, salesWTDGoal: 3, salesMTDGoal: 8),
        TeamMember(name: "Ron", quotesToday: 7, salesWTD: 1, salesMTD: 2, quotesGoal: 10, salesWTDGoal: 3, salesMTDGoal: 8),
        TeamMember(name: "Deanna", quotesToday: 5, salesWTD: 0, salesMTD: 1, quotesGoal: 10, salesWTDGoal: 3, salesMTDGoal: 8),
        TeamMember(name: "Dimitri", quotesToday: 8, salesWTD: 2, salesMTD: 3, quotesGoal: 10, salesWTDGoal: 3, salesMTDGoal: 8)
    ]
    
    @State private var selectedMember: TeamMember?
    @State private var editingMemberID: UUID?
    @State private var editingField: String = ""
    @State private var editingValue: Int = 0

    var body: some View {
        VStack {
            TabView {
                mainContent
                    .tabItem {
                        Label("Win the Day", systemImage: "checkmark.seal.fill")
                    }

                DashboardView()
                    .tabItem {
                        Label("Life Scoreboard", systemImage: "briefcase.fill")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Win the Day")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading) // Ensure it spans full width

                Menu {
                    Button(action: {
                        // Handle change activity action
                    }) {
                        Text("Change Activity")
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    Button(action: {
                        // Handle change goal action
                    }) {
                        Text("Change Goal")
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    Button(action: resetValues) {
                        Text("Reset")
                            .foregroundColor(.red) // Red color for the reset button
                        Image(systemName: "trash.fill") // Optional trash icon for reset
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 15) {
                    ForEach(team) { member in
                        // Only allow tap/edit if the card is for the logged-in user
                        if member.name == selectedUserName {
                            Button(action: {
                                selectedMember = member
                            }) {
                                TeamCard(member: member, isEditable: true)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            // For other users, show a locked, non-editable card
                            TeamCard(member: member, isEditable: false)
                        }
                    }
                }
                .padding(.horizontal, 20) // Added horizontal padding for the ScrollView content
            }

            Spacer()
        }
        .background(Color(.systemGray6).ignoresSafeArea())
        .overlay(
            Group {
                if let editingID = editingMemberID,
                   let index = team.firstIndex(where: { $0.id == editingID }) {
                    VStack(spacing: 15) {
                        // Removed the title from the top of the input card, leaving only the steppers
                        HStack {
                            Text("Quotes Today")
                            Stepper(value: $team[index].quotesToday, in: 0...team[index].quotesGoal) {
                                Text("\(team[index].quotesToday)")
                            }
                        }

                        HStack {
                            Text("Sales WTD")
                            Stepper(value: $team[index].salesWTD, in: 0...team[index].salesWTDGoal) {
                                Text("\(team[index].salesWTD)")
                            }
                        }

                        HStack {
                            Text("Sales MTD")
                            Stepper(value: $team[index].salesMTD, in: 0...team[index].salesMTDGoal) {
                                Text("\(team[index].salesMTD)")
                            }
                        }

                        HStack {
                            Button("Cancel") {
                                editingMemberID = nil
                            }
                            Spacer()
                            Button("Save") {
                                editingMemberID = nil
                            }
                        }
                    }
                    .padding()
                    .frame(width: 280)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 8)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.4)))
                }
            }
        )
    }

    // Add isEditable parameter to TeamCard
    private func TeamCard(member: TeamMember, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🕶️ \(member.name)")
                .font(.title2.bold())
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 237/255, green: 29/255, blue: 36/255))
                .foregroundColor(.white)
                .cornerRadius(10, corners: [.topLeft, .topRight])

            // Only allow tap/edit on Quotes Today if editable, otherwise show as read-only
            StatRow(title: "Quotes Today", value: member.quotesToday, goal: member.quotesGoal, isEditable: isEditable) {
                if isEditable {
                    editingMemberID = member.id
                    editingField = "quotesToday"
                    editingValue = member.quotesToday
                }
            }
            StatRow(title: "Sales WTD", value: member.salesWTD, goal: member.salesWTDGoal, isEditable: false) {}
            StatRow(title: "Sales MTD", value: member.salesMTD, goal: member.salesMTDGoal, isEditable: false) {}
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 0)
    }

    // Add isEditable parameter to StatRow
    private func StatRow(title: String, value: Int, goal: Int, isEditable: Bool, onTap: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.title2.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 140, height: 12)
                    .padding(.leading, 10)
                Capsule()
                    .fill(Color.blue)
                    .frame(
                        width: goal > 0 ? CGFloat(value) / CGFloat(goal) * 140 : 0,
                        height: 12
                    )
                    .padding(.leading, 10)
            }

            // Always show the stat text, and for non-editable Quotes Today, ensure it's not gray
            if !isEditable && title == "Quotes Today" {
                Text("\(value) / \(goal)")
                    .font(.title2.bold())
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .frame(width: 70, alignment: .trailing)
            } else {
                Text("\(value) / \(goal)")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditable {
                onTap()
            }
        }
        // Remove opacity change for Quotes Today, always keep visible and styled
        .opacity(1.0)
        .overlay(
            Group {
                if !isEditable && title == "Quotes Today" {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                        .padding(.trailing, 6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        )
    }

    // Reset function to reset values
    private func resetValues() {
        for index in team.indices {
            team[index].quotesToday = 0
            team[index].salesWTD = 0
            team[index].salesMTD = 0
        }
    }
}

struct TeamMember: Identifiable, Codable {
    var id = UUID()
    var name: String
    var quotesToday: Int
    var salesWTD: Int
    var salesMTD: Int
    var quotesGoal: Int
    var salesWTDGoal: Int
    var salesMTDGoal: Int
}

struct WinTheDayView_Previews: PreviewProvider {
    static var previews: some View {
        WinTheDayView()
    }
}
