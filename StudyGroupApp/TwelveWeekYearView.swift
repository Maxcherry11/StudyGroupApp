import SwiftUI

struct TwelveWeekYearView: View {
    @StateObject private var viewModel: TwelveWeekYearViewModel
    @ObservedObject private var userManager = UserManager.shared
    @State private var selectedMember: TwelveWeekMember? = nil
    @State private var isInteracting = false
    @State private var stableMemberOrder: [TwelveWeekMember] = []
    @State private var lastVisibleMemberId: UUID?
    @State private var interactionTimer: Timer?
    @State private var isScrolling = false
    @State private var currentDate = Date()
    @Environment(\.sizeCategory) private var sizeCategory
    @ScaledMetric(relativeTo: .largeTitle) private var titleBase: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var labelBase: CGFloat = 30

    init(viewModel: TwelveWeekYearViewModel = TwelveWeekYearViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var overallPercent: Double {
        guard !viewModel.members.isEmpty else { return 0 }
        return viewModel.members.map { $0.progress * 100 }.reduce(0, +) / Double(viewModel.members.count)
    }
    
    var currentQuarterWeeksRemaining: Int {
        let calendar = Calendar.current
        let now = currentDate
        
        // Get the current quarter (1-4)
        let quarter = (calendar.component(.month, from: now) - 1) / 3 + 1
        
        // Calculate the start of the current quarter
        let quarterStartMonth: Int
        switch quarter {
        case 1: quarterStartMonth = 1   // Jan-Mar
        case 2: quarterStartMonth = 4   // Apr-Jun
        case 3: quarterStartMonth = 7   // Jul-Sep
        case 4: quarterStartMonth = 10  // Oct-Dec
        default: quarterStartMonth = 1
        }
        
        // Create the start date of the current quarter
        var quarterStartComponents = DateComponents()
        quarterStartComponents.year = calendar.component(.year, from: now)
        quarterStartComponents.month = quarterStartMonth
        quarterStartComponents.day = 1
        
        guard let quarterStart = calendar.date(from: quarterStartComponents) else { return 12 }
        
        // Calculate the end of the current quarter (12 weeks from start)
        let _ = calendar.date(byAdding: .weekOfYear, value: 12, to: quarterStart) ?? now
        
        // Calculate weeks remaining in the current quarter
        let weeksElapsed = calendar.dateComponents([.weekOfYear], from: quarterStart, to: now).weekOfYear ?? 0
        let weeksRemaining = max(0, 12 - weeksElapsed)
        
        return weeksRemaining
    }

    var displayTeam: [TwelveWeekMember] {
        // If user is interacting or scrolling, use stable order; otherwise use sorted order
        if isInteracting || isScrolling {
            return stableMemberOrder
        } else {
            return sortedTeam
        }
    }

    var sortedTeam: [TwelveWeekMember] {
        guard !viewModel.members.isEmpty else { return [] }
        return viewModel.members.sorted { $0.progress > $1.progress }
    }
    
    // (Removed adaptive helpers)
    
    private func setInteracting(_ interacting: Bool) {
        isInteracting = interacting
        
        if interacting {
            // Cancel any existing timer
            interactionTimer?.invalidate()
        } else {
            // Set a timer to reset interaction state after a delay
            interactionTimer?.invalidate()
            interactionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                DispatchQueue.main.async {
                    if !isInteracting && !isScrolling {
                        // Only reset if still not interacting and not scrolling
                        stableMemberOrder = sortedTeam
                    }
                }
            }
        }
    }
    
    private func setScrolling(_ scrolling: Bool) {
        isScrolling = scrolling
        
        if scrolling {
            // Cancel any existing timer
            interactionTimer?.invalidate()
        } else {
            // Set a timer to reset interaction state after a delay
            interactionTimer?.invalidate()
            interactionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                DispatchQueue.main.async {
                    if !isInteracting && !isScrolling {
                        // Only reset if still not interacting and not scrolling
                        stableMemberOrder = sortedTeam
                    }
                }
            }
        }
    }
    
    private func resetInteractionState() {
        isInteracting = false
        isScrolling = false
        interactionTimer?.invalidate()
        interactionTimer = nil
        // Update stable order when resetting
        stableMemberOrder = sortedTeam
    }

    var body: some View {
        buildMainView()
            .refreshable {
                viewModel.fetchMembersFromCloud()
            }
            .onChange(of: userManager.userList) { _ in
                viewModel.fetchMembersFromCloud()
            }
            .onChange(of: viewModel.members) { newMembers in
                // Update stable order when members change, but only if not interacting
                if !isInteracting && !isScrolling {
                    stableMemberOrder = newMembers.sorted { $0.progress > $1.progress }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Update current date when app becomes active
                currentDate = Date()
            }
            .onAppear {
                // Initialize stable order
                stableMemberOrder = sortedTeam
                // Reset interaction state
                resetInteractionState()
                // Update current date immediately
                currentDate = Date()
                
                // Set up periodic timer to update stable order when not interacting
                interactionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                    DispatchQueue.main.async {
                        if !isInteracting && !isScrolling {
                            stableMemberOrder = sortedTeam
                        }
                    }
                }
                
                // Set up timer to update current date every hour to keep weeks remaining current
                Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                    DispatchQueue.main.async {
                        currentDate = Date()
                    }
                }
            }
            .onDisappear {
                // Clean up timer
                resetInteractionState()
            }
    }

    @ViewBuilder
    private func buildMainView() -> some View {
        ZStack(alignment: .top) {
            Color(red: 60/255, green: 90/255, blue: 140/255)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollViewReader { scrollProxy in
                // Ensure keyboard doesn’t freeze layout and capture gestures on compact devices
                ScrollView {
                    LazyVStack(spacing: 15) {
                        Text("12 Week Year")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 2)
                        
                        Text("\(currentQuarterWeeksRemaining) Weeks Remaining")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .cornerRadius(20)
                            .padding(.bottom, 55)

                        GaugeView(percentage: overallPercent)
                            .frame(height: 140)
                            .padding(.bottom, 10)

                        Text("On-Time % for Team")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))

                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(displayTeam, id: \.id) { member in
                                HStack {
                                    let isCurrent = member.name == userManager.currentUser
                                    Text(member.name)
                                            .font(.system(size: 26, weight: isCurrent ? .bold : .medium))
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
                                    // Allow any user to view any member's card
                                    // Editing restrictions are handled in CardView
                                    scrollProxy.scrollTo(member.id, anchor: .top)
                                    selectedMember = member
                                }
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.35)
                                        .onChanged { _ in setInteracting(true) }
                                        .onEnded { _ in setInteracting(false) }
                                )
                                .onAppear {
                                    lastVisibleMemberId = member.id
                                }
                                .onDisappear {
                                    if lastVisibleMemberId == member.id {
                                        lastVisibleMemberId = nil
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 70 : 15)
                    .padding(.horizontal, 16)
                    .scaleEffect(UIDevice.current.userInterfaceIdiom == .pad ? 0.75 : 1.0)
                }
                .ignoresSafeArea(.keyboard)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in setScrolling(true) }
                        .onEnded { _ in setScrolling(false) }
                )
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 64) }
                .onChange(of: isInteracting) { newValue in
                    if !newValue {
                        // When interaction ends, allow resorting next time members update
                    }
                }
                .transaction { t in t.disablesAnimations = isInteracting }
            }
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
                CardView(member: binding, isInteracting: Binding(
                    get: { isInteracting },
                    set: { setInteracting($0) }
                ), resetInteraction: resetInteractionState)
                    .environmentObject(viewModel)
                    .onDisappear {
                        viewModel.saveMember(binding.wrappedValue)
                        resetInteractionState()
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Back") {
                                resetInteractionState()
                                selectedMember = nil
                            }
                        }
                    }
            }
        }
        .onChange(of: selectedMember) { newValue in
            if newValue == nil {
                resetInteractionState()
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

// (Removed scroll offset tracking)
