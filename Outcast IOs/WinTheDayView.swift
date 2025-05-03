import SwiftUI

struct ContentView: View {
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

struct WinTheDayView: View {
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @Environment(\.presentationMode) var presentationMode

    public init() {}

    public var body: some View {
        VStack(spacing: 30) {
            Text("Win the Day!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 60)
            if !selectedUserName.isEmpty {
                Text("Welcome, \(selectedUserName)!")
                    .font(.title2)
                    .padding(.bottom, 40)
            }
            Spacer()
            Button("Back to User Selector") {
                // Clear selected user and pop to root
                selectedUserName = ""
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.bottom, 40)
        }
    }
}

struct StatSectionView: View {
    var title: String
    @Binding var value: Int
    var showGoal: Bool = false
    var goal: Int = 0
    var saveAction: () -> Void
    @Binding var triggerConfetti: Bool
    var isEditable: Bool

    @State private var showOnTimeIcon = false

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("\(title):")
                    .font(.title3)
                    .padding(.trailing, 4)
                // Use String for tempValue to ensure StringProtocol compatibility
                TextField("", value: $value, formatter: numberFormatter)
                    .disabled(!isEditable)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(PlainTextFieldStyle())
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 1)
                    .frame(width: 35)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                if showGoal {
                    Text("/ \(goal)")
                        .font(.title3)
                }
            }
            .padding(.vertical, 2)
            if showGoal {
                ZStack {
                    GeometryReader { geometry in
                        let calendar = Calendar.current
                        let today = Date()
                        let weekday = calendar.component(.weekday, from: today)
                        let dayIndex = max(weekday - 2, 0)
                        let isMonthly = title.lowercased().contains("month")
                        let totalDays = isMonthly
                            ? calendar.range(of: .day, in: .month, for: today)?.count ?? 30
                            : 5
                        let currentDay = isMonthly
                            ? calendar.component(.day, from: today)
                            : min(dayIndex + 1, 5)
                        let dailyTarget = Double(goal) / Double(totalDays)
                        let expectedTotal = ceil(Double(currentDay) * dailyTarget)
                        // Ensure progress bar fills to 100% when value >= goal
                        let progress = goal > 0 ? min(CGFloat(value) / CGFloat(goal), 1.0) : 0.0
                        let isOnTrack = Double(value) >= expectedTotal
                        let barColor: Color = (value == 0) ? .gray : (isOnTrack ? .green : .yellow)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 5)
                            Capsule()
                                .fill(barColor)
                                .frame(width: progress * geometry.size.width, height: 5)
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 4)
                    // Show the celebration emoji above the bar when on time
                    if showOnTimeIcon {
                        Text("🎉")
                            .font(.title2)
                            .transition(.scale)
                            .offset(y: -28)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .onChange(of: value) { newValue in
            saveAction()
            // Confetti triggers when goal is met or exceeded
            if showGoal && goal > 0 && newValue >= goal {
                withAnimation {
                    triggerConfetti = true
                }
            }
            // Icon for being on time (not necessarily goal met)
            let calendar = Calendar.current
            let today = Date()
            let weekday = calendar.component(.weekday, from: today)
            let dayIndex = max(weekday - 2, 0)
            let isMonthly = title.lowercased().contains("month")
            let totalDays = isMonthly
                ? calendar.range(of: .day, in: .month, for: today)?.count ?? 30
                : 5
            let currentDay = isMonthly
                ? calendar.component(.day, from: today)
                : min(dayIndex + 1, 5)
            let dailyTarget = goal > 0 ? Double(goal) / Double(totalDays) : 0.0
            let expectedTotal = ceil(Double(currentDay) * dailyTarget)
            if showGoal && Double(newValue) >= expectedTotal {
                withAnimation {
                    showOnTimeIcon = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showOnTimeIcon = false
                    }
                }
            }
        }
    }
}

struct TeamMember: Identifiable, Codable {
    var id = UUID()
    var name: String
    // Current performance values
    var quotesToday: Int
    var salesWTD: Int
    var salesMTD: Int
    // Goal values
    var quotesGoal: Int
    var salesWTDGoal: Int
    var salesMTDGoal: Int
    
    var totalScore: Int {
        quotesToday + salesWTD + salesMTD
    }
}

struct WinTheDayView_Previews: PreviewProvider {
    static var previews: some View {
        WinTheDayView()
    }
}

import UIKit

struct ConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: UIScreen.main.bounds.width, height: 2.0)

        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPink, .systemYellow, .cyan, .magenta]
        var cells: [CAEmitterCell] = []

        let shapes: [String] = ["circle", "square", "triangle"]
        for color in colors {
            for shape in shapes {
                let cell = CAEmitterCell()
                cell.birthRate = 4
                cell.lifetime = 6.0
                cell.velocity = 200
                cell.velocityRange = 50
                cell.emissionLongitude = .pi
                cell.emissionRange = .pi / 4
                cell.spin = 3
                cell.spinRange = 2
                cell.scale = [0.4, 0.6, 0.8].randomElement()!
                cell.scaleRange = 0.3
                cell.color = color.cgColor
                cell.contents = makeConfettiImage(color: color, shape: shape).cgImage
                cells.append(cell)
            }
        }

        emitter.emitterCells = cells
        view.layer.addSublayer(emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            emitter.birthRate = 0
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
    // Helper method to generate a colored shape image for confetti
    private func makeConfettiImage(color: UIColor, shape: String, size: CGSize = CGSize(width: 8, height: 8)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            switch shape {
            case "square":
                context.cgContext.fill(CGRect(origin: .zero, size: size))
            case "triangle":
                context.cgContext.beginPath()
                context.cgContext.move(to: CGPoint(x: size.width / 2, y: 0))
                context.cgContext.addLine(to: CGPoint(x: size.width, y: size.height))
                context.cgContext.addLine(to: CGPoint(x: 0, y: size.height))
                context.cgContext.closePath()
                context.cgContext.fillPath()
            default:
                context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            }
        }
    }
}

struct TeamMemberCard: View {
    @Binding var member: TeamMember
    let userName: String
    let screenWidth: CGFloat
    let index: Int
    let animateCards: Bool
    let showFullScreenConfetti: Binding<Bool>
    let saveAction: () -> Void

    // Use unique AppStorage keys per user name for profile image and emoji
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @AppStorage("profileImageData_DJ") private var profileImageData_DJ: Data?
    @AppStorage("profileEmoji_DJ") private var profileEmoji_DJ: String?
    @AppStorage("profileImageData_Ron") private var profileImageData_Ron: Data?
    @AppStorage("profileEmoji_Ron") private var profileEmoji_Ron: String?
    @AppStorage("profileImageData_Deanna") private var profileImageData_Deanna: Data?
    @AppStorage("profileEmoji_Deanna") private var profileEmoji_Deanna: String?
    @AppStorage("profileImageData_Dimitri") private var profileImageData_Dimitri: Data?
    @AppStorage("profileEmoji_Dimitri") private var profileEmoji_Dimitri: String?

    // Custom prompt labels
    @AppStorage("quotesPrompt") private var quotesPrompt: String = "Quotes Today"
    @AppStorage("salesWTDPrompt") private var salesWTDPrompt: String = "Sales WTD"
    @AppStorage("salesMTDPrompt") private var salesMTDPrompt: String = "Sales MTD"


    var body: some View {
        let isEditable = member.name == userName
        // Dynamically scale padding, font, and spacing based on device width
        let horizontalPadding = max(10, screenWidth * 0.04)
        let verticalPadding = max(6, screenWidth * 0.015)
        let cardSpacing = max(10, screenWidth * 0.03)
        let cardFont = Font.system(size: max(15, screenWidth * 0.045), weight: .bold)
        let cardTitleFont = Font.system(size: max(15, screenWidth * 0.045), weight: .bold)
        let cardInnerPadding = max(8, screenWidth * 0.03)
        let cardOuterPadding = max(8, screenWidth * 0.02)
        let cardCornerRadius = max(10, screenWidth * 0.025)
        let cardShadowRadius = max(2, screenWidth * 0.008)
        return VStack(alignment: .leading, spacing: cardSpacing) {
            HStack {
                Text(member.name)
                if isEditable {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .font(cardTitleFont)
            .foregroundColor(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Color(red: 227/255, green: 6/255, blue: 19/255))
            .cornerRadius(cardCornerRadius)

            StatRow(title: quotesPrompt, value: $member.quotesToday, goal: member.quotesGoal, onSave: saveAction, isEditable: isEditable, triggerConfetti: showFullScreenConfetti, screenWidth: screenWidth)
            StatRow(title: salesWTDPrompt, value: $member.salesWTD, goal: member.salesWTDGoal, onSave: saveAction, isEditable: isEditable, triggerConfetti: showFullScreenConfetti, screenWidth: screenWidth)
            StatRow(title: salesMTDPrompt, value: $member.salesMTD, goal: member.salesMTDGoal, onSave: saveAction, isEditable: isEditable, triggerConfetti: showFullScreenConfetti, screenWidth: screenWidth)
        }
        .padding(cardInnerPadding)
        .background(Color.white.opacity(0.95))
        .cornerRadius(cardCornerRadius)
        .shadow(color: .black.opacity(0.1), radius: cardShadowRadius, x: 0, y: 2)
        .padding(.horizontal, cardOuterPadding)
        .offset(x: animateCards ? 0 : screenWidth)
        .animation(
            .easeOut(duration: 0.5)
                .delay(Double(index) * 0.05),
            value: animateCards
        )
    }
}
 


struct StatRow: View {
    let title: String
    @Binding var value: Int
    let goal: Int
    let onSave: () -> Void
    let isEditable: Bool
    @Binding var triggerConfetti: Bool
    var screenWidth: CGFloat = UIScreen.main.bounds.width

    @State private var showEditor = false
    @State private var tempValue: String = ""
    @State private var showOnTimeIcon = false

    // Computed property for progress and bar color based on weekday
    private var progressInfo: (progress: CGFloat, barColor: Color) {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let dayIndex = max(weekday - 2, 0)
        let titleString: String = String(title)
        let isMonthly = titleString.lowercased().contains("month")
        let totalDays = isMonthly
            ? calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            : 5
        let currentDay = isMonthly
            ? calendar.component(.day, from: today)
            : min(dayIndex + 1, 5)
        let dailyTarget = goal > 0 ? Double(goal) / Double(totalDays) : 0.0
        let expectedTotal = ceil(Double(currentDay) * dailyTarget)
        // Progress bar fills to 100% when goal met or exceeded
        let progress = goal > 0 ? min(CGFloat(value) / CGFloat(goal), 1.0) : 0.0
        let isOnTrack = Double(value) >= expectedTotal
        let barColor: Color = (value == 0) ? .gray : (isOnTrack ? .green : .yellow)
        return (progress, barColor)
    }

    var body: some View {
        // Responsive sizing
        let rowFont = Font.system(size: max(14, screenWidth * 0.042), weight: .bold)
        let statFont = Font.system(size: max(14, screenWidth * 0.042), weight: .bold)
        let capsuleHeight = max(12, screenWidth * 0.035)
        let capsuleWidth = max(110, screenWidth * 0.36)
        let statWidth = max(48, screenWidth * 0.16)
        let iconFont = Font.system(size: max(20, screenWidth * 0.06))
        let rowPadding = max(4, screenWidth * 0.01)
        HStack {
            Text(title)
                .font(rowFont)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Spacer()
            ZStack(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(progressInfo.barColor)
                        .frame(width: progressInfo.progress * geometry.size.width)
                }
            }
            .frame(width: capsuleWidth, height: capsuleHeight)
            .clipShape(Capsule())
            if showOnTimeIcon {
                Text("🎉")
                    .font(iconFont)
                    .transition(.scale)
                    .offset(y: -capsuleHeight)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(value) / \(goal)")
                    .font(statFont)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(width: statWidth)
        }
        .padding(.horizontal, rowPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditable {
                tempValue = ""
                showEditor = true
            }
        }
        .alert("Update \(title)", isPresented: $showEditor) {
            TextField("New Value", text: $tempValue)
                .keyboardType(.numberPad)
            Button("Save", action: {
                if let newVal = Int(tempValue) {
                    value = newVal
                    onSave()
                    if newVal >= goal {
                        withAnimation {
                            triggerConfetti = true
                        }
                    }
                    // Icon for being on time (not necessarily goal met)
                    let calendar = Calendar.current
                    let today = Date()
                    let weekday = calendar.component(.weekday, from: today)
                    let dayIndex = max(weekday - 2, 0)

                    let isMonthly = title.lowercased().contains("month")
                    let totalDays = isMonthly
                        ? calendar.range(of: .day, in: .month, for: today)?.count ?? 30
                        : 5

                    let currentDay = isMonthly
                        ? calendar.component(.day, from: today)
                        : min(dayIndex + 1, 5)

                    let dailyTarget = Double(goal) / Double(totalDays)
                    let expectedTotal = ceil(Double(currentDay) * dailyTarget)

                    if Double(newVal) >= expectedTotal {
                        withAnimation {
                            showOnTimeIcon = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showOnTimeIcon = false
                            }
                        }
                    }
                }
            })
            Button("Cancel", role: .cancel) {}
        }
    }
}



// MARK: - Color extension for hex support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

 

struct GoalEditorView: View {
    @Binding var teamData: [TeamMember]
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @Environment(\.dismiss) private var dismiss

    struct GoalEditorMember: Identifiable {
        let id: UUID
        var name: String
        var quotesGoal: String
        var salesWTDGoal: String
        var salesMTDGoal: String
    }

    // Add prompt storage for dynamic goal labels
    @AppStorage("quotesPrompt") private var quotesPrompt: String = "Quotes Today"
    @AppStorage("salesWTDPrompt") private var salesWTDPrompt: String = "Sales WTD"
    @AppStorage("salesMTDPrompt") private var salesMTDPrompt: String = "Sales MTD"

    @State private var editedMembers: [GoalEditorMember] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Only show the card for the selected user using explicit index binding
                    if !selectedUserName.isEmpty,
                       let index = editedMembers.firstIndex(where: { $0.name == selectedUserName }) {
                        let member = $editedMembers[index]
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Edit Goals")
                                .font(.title2.bold())
                                .padding(.bottom, 4)

                            HStack {
                                TextField("Label", text: $quotesPrompt)
                                    .font(.body)
                                    .frame(width: 110)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Spacer()
                                TextField(quotesPrompt, text: member.quotesGoal)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            HStack {
                                TextField("Label", text: $salesWTDPrompt)
                                    .font(.body)
                                    .frame(width: 110)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Spacer()
                                TextField(salesWTDPrompt, text: member.salesWTDGoal)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            HStack {
                                TextField("Label", text: $salesMTDPrompt)
                                    .font(.body)
                                    .frame(width: 110)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Spacer()
                                TextField(salesMTDPrompt, text: member.salesMTDGoal)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6)) // Revert: card background to gray
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            .navigationTitle("Edit Goals")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        for edited in editedMembers {
                            if let index = teamData.firstIndex(where: { $0.id == edited.id }) {
                                teamData[index].quotesGoal = Int(edited.quotesGoal) ?? 0
                                teamData[index].salesWTDGoal = Int(edited.salesWTDGoal) ?? 0
                                teamData[index].salesMTDGoal = Int(edited.salesMTDGoal) ?? 0
                            }
                        }
                        dismiss()
                    }
                }
            }
            .background(Color.gray.opacity(0.3)) // Lighter gray for readability
            .onAppear {
                editedMembers = teamData.map {
                    GoalEditorMember(
                        id: $0.id,
                        name: $0.name,
                        quotesGoal: $0.quotesGoal == 0 ? "" : String($0.quotesGoal),
                        salesWTDGoal: $0.salesWTDGoal == 0 ? "" : String($0.salesWTDGoal),
                        salesMTDGoal: $0.salesMTDGoal == 0 ? "" : String($0.salesMTDGoal)
                    )
                }
            }
        }
    }
}

struct PromptEditorView: View {
    @AppStorage("quotesPrompt") private var quotesPrompt: String = "Quotes Today"
    @AppStorage("salesWTDPrompt") private var salesWTDPrompt: String = "Sales WTD"
    @AppStorage("salesMTDPrompt") private var salesMTDPrompt: String = "Sales MTD"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 18) {
                        TextField("Quotes Prompt", text: $quotesPrompt)
                            .padding(10)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        TextField("Sales WTD Prompt", text: $salesWTDPrompt)
                            .padding(10)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        TextField("Sales MTD Prompt", text: $salesMTDPrompt)
                            .padding(10)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .padding(.horizontal)
                }
            }
            .background(Color.gray.opacity(0.3).ignoresSafeArea())
            .navigationTitle("Edit Prompts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}



// MARK: - UserNameEditorField
/// A text field for editing a user's name, managing its own state for smooth editing and deletion.
fileprivate struct UserNameEditorField: View {
    @State private var text: String
    let onCommit: (String) -> Void
    let onTextChange: (String) -> Void
    var isFocused: Bool
    var onFocus: (() -> Void)?
    let name: String
    @FocusState private var fieldIsFocused: Bool

    init(name: String,
         onCommit: @escaping (String) -> Void,
         onTextChange: @escaping (String) -> Void,
         isFocused: Bool,
         onFocus: (() -> Void)? = nil
    ) {
        self.name = name
        _text = State(initialValue: name)
        self.onCommit = onCommit
        self.onTextChange = onTextChange
        self.isFocused = isFocused
        self.onFocus = onFocus
    }

    var body: some View {
        // Use a custom TextField with .focused and .onChange for smooth focus and text handling.
        TextField(
            "",
            text: $text,
            onEditingChanged: { editing in
                if editing {
                    onFocus?()
                }
            },
            onCommit: {
                onCommit(text)
            }
        )
        .font(.title2)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(red: 235/255, green: 242/255, blue: 255/255))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.6), lineWidth: 2)
        )
        .cornerRadius(8)
        .overlay(
            HStack {
                Spacer()
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
                    .padding(.trailing, 12)
            }
            .allowsHitTesting(false)
        )
        .disableAutocorrection(true)
        .textInputAutocapitalization(.words)
        .focused($fieldIsFocused)
        .onChange(of: isFocused) { newVal in
            // Keep focus in sync with parent (UserSelectorView)
            if newVal && !fieldIsFocused {
                fieldIsFocused = true
            }
        }
        .onChange(of: fieldIsFocused) { newVal in
            // If the field gains focus, notify parent to update focus state
            if newVal, !isFocused {
                onFocus?()
            }
        }
        .onChange(of: text) { newText in
            // Always propagate changes, including full deletion, for live updates.
            onTextChange(newText)
        }
        .onChange(of: name) { newName in
            // If the parent changes the name (e.g. after duplicate check), reset text.
            if newName != text {
                text = newName
            }
        }
        .onAppear {
            // Ensure initial focus state matches parent
            if isFocused {
                fieldIsFocused = true
            }
        }
    }
}
 


