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
                        Label("12 Week Year", systemImage: "calendar")
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
                Button(action: {
                    // Future settings action
                }) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 15) {
                    ForEach(team) { member in
                        Button(action: {
                            selectedMember = member
                        }) {
                            TeamCard(member: member)
                        }
                        .buttonStyle(PlainButtonStyle())
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
                        Text("Edit \(editingField)")
                            .font(.headline)
                        Stepper("\(editingValue)", value: $editingValue)
                        HStack {
                            Button("Cancel") {
                                editingMemberID = nil
                            }
                            Spacer()
                            Button("Save") {
                                switch editingField {
                                case "quotesToday": team[index].quotesToday = editingValue
                                case "salesWTD": team[index].salesWTD = editingValue
                                case "salesMTD": team[index].salesMTD = editingValue
                                default: break
                                }
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

    private func TeamCard(member: TeamMember) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🕶️ \(member.name)")
                .font(.title2.bold())
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 237/255, green: 29/255, blue: 36/255)) // Red background spans full width
                .foregroundColor(.white)
                .cornerRadius(10, corners: [.topLeft, .topRight]) // Top corners rounded for consistency

            StatRow(title: "Quotes Today", value: member.quotesToday, goal: member.quotesGoal) {
                editingMemberID = member.id
                editingField = "quotesToday"
                editingValue = member.quotesToday
            }
            StatRow(title: "Sales WTD", value: member.salesWTD, goal: member.salesWTDGoal) {
                editingMemberID = member.id
                editingField = "salesWTD"
                editingValue = member.salesWTD
            }
            StatRow(title: "Sales MTD", value: member.salesMTD, goal: member.salesMTDGoal) {
                editingMemberID = member.id
                editingField = "salesMTD"
                editingValue = member.salesMTD
            }
        }
        .padding(12) // Adjusted padding for the card
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
        .frame(maxWidth: 520) // Reduced max width to prevent overflow
        .padding(.horizontal, 15) // Horizontal padding to fit within screen
    }

    private func StatRow(title: String, value: Int, goal: Int, onTap: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.body.bold())
                .lineLimit(1) // Prevents the text from breaking into multiple lines
                .frame(width: 100, alignment: .leading) // Ensure the title has fixed width

            Spacer()
            
            ZStack(alignment: .leading) {
                // Gray background (inactive part of progress)
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 12) // Progress bar width
                    .padding(.leading, 10)
                // Blue progress bar (active part of progress)
                Capsule()
                    .fill(Color.blue)
                    .frame(
                        width: goal > 0 ? CGFloat(value) / CGFloat(goal) * 180 : 0, // Adjusted width dynamically
                        height: 12
                    )
                    .padding(.leading, 10)
            }

            Text("\(value) / \(goal)")
                .font(.body.bold())
                .lineLimit(1) // Prevents the text from breaking into multiple lines
                .frame(width: 80, alignment: .trailing) // Ensure the text has fixed width
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
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
