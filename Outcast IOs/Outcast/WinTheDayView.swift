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
    @AppStorage("savedTeam") private var savedTeamData: Data = Data()
    @Environment(\.presentationMode) var presentationMode

    @State private var team: [TeamMember] = [
        TeamMember(name: "D.J.", quotesToday: 10, salesWTD: 2, salesMTD: 5, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8),
        TeamMember(name: "Ron", quotesToday: 7, salesWTD: 1, salesMTD: 2, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8),
        TeamMember(name: "Deanna", quotesToday: 5, salesWTD: 0, salesMTD: 1, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8),
        TeamMember(name: "Dimitri", quotesToday: 8, salesWTD: 2, salesMTD: 3, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8)
    ]
    @State private var recentlyCompletedIDs: Set<UUID> = []
    
    @State private var selectedMember: TeamMember?
    @State private var editingMemberID: UUID?
    @State private var editingField: String = ""
    @State private var editingValue: Int = 0
    @State private var emojiPickerVisible: Bool = false
    @State private var emojiEditingID: UUID?

    @State private var shimmerPosition: CGFloat = -1.0

    var body: some View {
        VStack {
            TabView {
                mainContent
                    .tabItem {
                        Label("Win the Day", systemImage: "checkmark.seal.fill")
                    }
                    .onAppear {
                        // Load team from savedTeamData if possible
                        if let loadedTeam = try? JSONDecoder().decode([TeamMember].self, from: savedTeamData), !loadedTeam.isEmpty {
                            team = loadedTeam
                        }
                    }
                    .onDisappear {
                        // Save team to savedTeamData
                        if let encoded = try? JSONEncoder().encode(team) {
                            savedTeamData = encoded
                        }
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button(action: {
                        // Handle change activity action
                    }) {
                        Text("Change Activity")
                        Image(systemName: "circle")
                    }
                    Button(action: {
                        // Handle change goal action
                    }) {
                        Text("Change Goal")
                        Image(systemName: "circle")
                    }
                    Button(action: resetValues) {
                        Text("Reset")
                            .foregroundColor(.red)
                        Image(systemName: "trash.fill")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Restore ScrollView with VStack, remove GeometryReader and dynamic frame
            ScrollView {
                let sortedTeam = team.sorted { lhs, rhs in
                    let lhsScore = lhs.quotesToday + lhs.salesWTD * 3 + lhs.salesMTD * 2
                    let rhsScore = rhs.quotesToday + rhs.salesWTD * 3 + rhs.salesMTD * 2
                    return lhsScore > rhsScore
                }
                VStack(spacing: 10) {
                    ForEach(sortedTeam) { member in
                        // Only allow tap/edit if the card is for the logged-in user
                        if member.name == selectedUserName {
                            Button(action: {
                                selectedMember = member
                            }) {
                                TeamCard(member: member, isEditable: true)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            TeamCard(member: member, isEditable: false)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .background(
            ZStack {
                backgroundGradient(for: team).ignoresSafeArea()
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.25),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 400)
                .rotationEffect(.degrees(30))
                .offset(x: shimmerPosition * 600)
                .blendMode(.overlay)
                .ignoresSafeArea()
            }
        )
        .onAppear {
            withAnimation(Animation.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerPosition = 1.0
            }
        }
        .overlay(
            Group {
                if let editingID = editingMemberID,
                   let index = team.firstIndex(where: { $0.id == editingID }) {
                    VStack(spacing: 15) {
                        if editingField == "quotesToday" {
                            HStack {
                                Text("Quotes Today")
                                Stepper(value: $team[index].quotesToday, in: 0...1000) {
                                    Text("\(team[index].quotesToday)")
                                }
                            }
                        } else if editingField == "salesWTD" {
                            HStack {
                                Text("Sales WTD")
                                Stepper(value: $team[index].salesWTD, in: 0...1000) {
                                    Text("\(team[index].salesWTD)")
                                }
                            }
                        } else if editingField == "salesMTD" {
                            HStack {
                                Text("Sales MTD")
                                Stepper(value: $team[index].salesMTD, in: 0...1000) {
                                    Text("\(team[index].salesMTD)")
                                }
                            }
                        }
                        HStack {
                            Button("Cancel") {
                                editingMemberID = nil
                            }
                            Spacer()
                            Button("Save") {
                                if let id = editingMemberID,
                                   let index = team.firstIndex(where: { $0.id == id }) {
                                    let member = team[index]
                                    // Check if Quotes Today or Sales WTD just became on pace
                                    let nowGreen = ["Quotes Today", "Sales WTD"].contains { title in
                                        progressColor(for: title, value: valueFor(title, of: member), goal: goalFor(title, of: member)) == .green
                                    }
                                    if nowGreen {
                                        recentlyCompletedIDs.insert(member.id)
                                        // Auto-remove icon after delay
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            recentlyCompletedIDs.remove(member.id)
                                        }
                                    }
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
        .sheet(isPresented: $emojiPickerVisible) {
            VStack(spacing: 20) {
                Text("Choose Your Emoji").font(.headline)
                let emojis = [
                    "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇",
                    "🙂", "🙃", "😉", "😌", "😍", "😘", "😗", "😙", "😚", "😋",
                    "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔", "🤐", "😶",
                     "👩🏾", "👧🏽", "👨🏾", "👩🏿", "👩🏾‍🦱", "👱🏽‍♂️", "👨🏽‍🦲", "👨🏽‍💻",
                    "🧓🏾", "👴🏻", "👮🏽‍♂️", "👷🏾‍♀️", "💂🏿", "🕵🏻‍♂️", "👩🏼‍⚕️", "👨🏽‍🎓", "👩🏻‍🏫",
                    "👨🏾‍🏭", "👩🏿‍💻", "👨🏻‍💼", "👩🏼‍🔧", "👨🏽‍🔬", "👩🏾‍🎤", "👨🏾‍🦱", "👨🏿‍🦱", "👩🏽‍⚖️",
                    "🧑🏾‍🌾", "🧑🏿‍🍳", "🧑🏻‍🎨", "🧑🏼‍🔬", "🧑🏽‍✈️", "🧑🏾‍🚀", "🧑🏿‍⚖️", "🧑🏻‍⚕️", "🧑🏼‍🎓", "🧑🏽‍🏫",
                    "❤️", "🧡", "💛", "💚", "💙", "💜", "🤎", "🖤", "🤍", "💯",
                    "🌟", "⭐", "✨", "🔥", "🎉", "🎯", "🏆", "🎖", "🎓", "🎬",
                    "🎧", "🎮", "🎨", "🎼", "🕹", "🧠", "📚", "💡", "📈", "📅"
                ]
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(emojis.chunked(into: 8), id: \.self) { row in
                            HStack {
                                ForEach(row, id: \.self) { emoji in
                                    Button(action: {
                                        if let id = emojiEditingID,
                                           let index = team.firstIndex(where: { $0.id == id }) {
                                            team[index].emoji = emoji
                                        }
                                        emojiPickerVisible = false
                                    }) {
                                        Text(emoji)
                                            .font(.largeTitle)
                                    }
                                }
                            }
                        }
                    }
                }
                Button("Cancel") {
                    emojiPickerVisible = false
                }
            }
            .padding()
        }
    }

    // Add isEditable parameter to TeamCard
    private func TeamCard(member: TeamMember, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if isEditable {
                    Button(action: {
                        emojiEditingID = member.id
                        emojiPickerVisible = true
                    }) {
                        Text(member.emoji)
                            .font(.title2.bold())
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Text(member.emoji)
                        .font(.title2.bold())
                }
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.title2.bold())
                    if isEditable {
                        Image(systemName: "pencil")
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 237/255, green: 29/255, blue: 36/255))
            .foregroundColor(.white)
            .cornerRadius(10, corners: [.topLeft, .topRight])

            if isEditable {
                StatRow(title: "Quotes Today", value: member.quotesToday, goal: member.quotesGoal, isEditable: true) {
                    editingMemberID = member.id
                    editingField = "quotesToday"
                    editingValue = member.quotesToday
                }
                StatRow(title: "Sales WTD", value: member.salesWTD, goal: member.salesWTDGoal, isEditable: true) {
                    editingMemberID = member.id
                    editingField = "salesWTD"
                    editingValue = member.salesWTD
                }
                StatRow(title: "Sales MTD", value: member.salesMTD, goal: member.salesMTDGoal, isEditable: true) {
                    editingMemberID = member.id
                    editingField = "salesMTD"
                    editingValue = member.salesMTD
                }
            } else {
                StatRow(title: "Quotes Today", value: member.quotesToday, goal: member.quotesGoal, isEditable: false) {}
                StatRow(title: "Sales WTD", value: member.salesWTD, goal: member.salesWTDGoal, isEditable: false) {}
                StatRow(title: "Sales MTD", value: member.salesMTD, goal: member.salesMTDGoal, isEditable: false) {}
            }
        }
        .padding(6)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
        .frame(maxWidth: .infinity)
        // Remove any .frame(height: ...) modifiers here to avoid overlap
        .padding(.horizontal, 0) // line 362
        .overlay(
            VStack {
                Spacer()
                if recentlyCompletedIDs.contains(member.id) {
                    Text("🎉")
                        .font(.system(size: 40))
                        .scaleEffect(1.4)
                        .transition(.scale)
                        .padding(.bottom, 30)
                }
            }
            .animation(.easeOut(duration: 0.4), value: recentlyCompletedIDs.contains(member.id))
        )
    }

    // Add isEditable parameter to StatRow
    private func StatRow(title: String, value: Int, goal: Int, isEditable: Bool, onTap: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 140, height: 10)
                    .padding(.leading, 10)
                Capsule()
                    .fill(progressColor(for: title, value: value, goal: goal))
                    .frame(
                        width: goal > 0 ? min(CGFloat(value) / CGFloat(goal), 1.0) * 140 : 0,
                        height: 10
                    )
                    .padding(.leading, 10)
            }

            // Always show the stat text with consistent styling
            Text("\(value) / \(goal)")
                .font(.subheadline.bold())
                .foregroundColor(.black)
                .lineLimit(1)
                .frame(width: 90, alignment: .trailing)
        }
        .frame(height: 26)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditable {
                onTap()
            }
        }
        // Remove opacity change for Quotes Today, always keep visible and styled
        .opacity(1.0)
        // Removed overlay for lock icon
    }

    // Reset function to reset values
    private func resetValues() {
        for index in team.indices {
            team[index].quotesToday = 0
            team[index].salesWTD = 0
            team[index].salesMTD = 0
        }
    }

    // Background gradient based on team progress
    private func backgroundGradient(for team: [TeamMember]) -> LinearGradient {
        var totalActual = 0
        var totalGoal = 0

        for member in team {
            totalActual += member.quotesToday + member.salesWTD + member.salesMTD
            totalGoal += member.quotesGoal + member.salesWTDGoal + member.salesMTDGoal
        }

        guard totalGoal > 0 else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.3), Color.gray]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        let percent = Double(totalActual) / Double(totalGoal)

        let colors: [Color]
        switch percent {
        case 0:
            colors = [Color.gray.opacity(0.3), Color.gray]
        case 0..<0.25:
            colors = [Color.red.opacity(0.3), Color.red]
        case 0.25..<0.75:
            colors = [Color.yellow.opacity(0.3), Color.yellow]
        default:
            colors = [Color.green.opacity(0.3), Color.green]
        }

        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func progressColor(for title: String, value: Int, goal: Int) -> Color {
        guard goal > 0 else { return .gray }

        let calendar = Calendar.current
        let today = Date()

        switch title {
        case "Quotes Today", "Sales WTD":
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let pace = Double(goal) * Double(dayOfWeek) / 7.0
            return Double(value) >= pace ? .green : .yellow

        case "Sales MTD":
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let pace = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            return Double(value) >= pace ? .green : .yellow

        default:
            return .gray
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
    
    var emoji: String {
        get {
            UserDefaults.standard.string(forKey: "emoji-\(name)") ?? "🕶️"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "emoji-\(name)")
        }
    }
}
struct WinTheDayView_Previews: PreviewProvider {
    static var previews: some View {
        WinTheDayView()
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

    private func valueFor(_ title: String, of member: TeamMember) -> Int {
        switch title {
        case "Quotes Today": return member.quotesToday
        case "Sales WTD": return member.salesWTD
        case "Sales MTD": return member.salesMTD
        default: return 0
        }
    }

    private func goalFor(_ title: String, of member: TeamMember) -> Int {
        switch title {
        case "Quotes Today": return member.quotesGoal
        case "Sales WTD": return member.salesWTDGoal
        case "Sales MTD": return member.salesMTDGoal
        default: return 1
        }
    }
