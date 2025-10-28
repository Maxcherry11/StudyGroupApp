

import SwiftUI
import CloudKit
import Foundation
import UIKit

// MARK: - Trophy Streak Helpers (Time/Week)
private let chicagoTimeZone = TimeZone(identifier: "America/Chicago")!

// Helper functions moved to WinTheDayViewModel

// MARK: - Trophy Streak Persistence (Moved to WinTheDayViewModel)

// MARK: - Trophy Row View
private struct TrophyRowView: View {
    let count: Int
    var body: some View {
        // Right-justified, newest added to the left (visually grows leftward)
        HStack(spacing: 4) {
            ForEach(0..<max(0, count), id: \.self) { _ in
                Text("🏆")
                    .font(.system(size: 25))
            }
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

enum StatType {
    case quotes
    case salesWTD
    case salesMTD
}

struct WinTheDayView: View {
    @ObservedObject var viewModel: WinTheDayViewModel
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var cloud = CloudKitManager.shared
    @State private var shimmerPosition: CGFloat = 0
    @State private var editingMemberID: UUID?
    @State private var editingField: String = ""
    @State private var editingValue: Int = 0
    @State private var emojiPickerVisible = false
    @State private var emojiEditingID: UUID?
    @State private var recentlyCompletedIDs: Set<UUID> = []
    @State private var celebrationMemberID: UUID?
    @State private var celebrationField: String = ""
    @State private var confettiMemberID: UUID?
    // Keep editing state active during the delayed reorder window after Save
    @State private var isAwaitingDelayedReorder: Bool = false
    // Cache for frozen order while editing popup is open
    @State private var frozenOrderIDs: [UUID] = []
    // Allow animation only during the post-save reorder window
    @State private var isPerformingAnimatedReorder: Bool = false
    // Production Goal Editor State
    @State private var showProductionGoalEditor = false
    @State private var newQuotesGoal = 10
    @State private var newSalesWTDGoal = 2
    @State private var newSalesMTDGoal = 6
    // Goal Name Editor State
    @State private var showGoalNameEditor = false
    @State private var editingQuotesLabel = ""
    @State private var editingSalesWTDLabel = ""
    @State private var editingSalesMTDLabel = ""
    @State private var didRunInitialSync = false
    // Caches for splash-to-dashboard transition
    @State private var lastNonEmptyMembers: [TeamMember] = []
    @State private var lastNonEmptyTeamData: [TeamMember] = []

    // Bootstrap flag to prevent initial blink during first data load
    @State private var isBootstrapping: Bool = false

    // Trophy finalization is now handled in WinTheDayViewModel

    // Check if view model is already warm when view is created
    private var shouldBootstrap: Bool {
        // If view model is warm, no need to bootstrap
        if viewModel.isWarm {
            return false
        }
        // If we have data already, no need to bootstrap
        if !viewModel.teamMembers.isEmpty || !viewModel.teamData.isEmpty {
            return false
        }
        // Otherwise, we need to bootstrap
        return true
    }

    // Removed computed properties to avoid compiler type-checking issues

    // DEBUG: order logging
    @State private var enableOrderLogs = true
    private func logOrder(_ label: String, _ members: [TeamMember]) {
        guard enableOrderLogs else { return }
        let names = members.map { $0.name }.joined(separator: ", ")
        print("🧭 [WinTheDay] \(label): [\(names)]")
    }

    // Break up the large body chain for compiler performance
    private var lifecycleWrapped: some View {
        VStack(spacing: 20) {
            header
            teamCardsList
            fallbackMessage
            Spacer()
        }
        .overlay(editingOverlay)
        .overlay(confettiOverlay)
        .background(winTheDayBackground)
        .opacity(isBootstrapping ? 0 : 1) // hide until first stable frame is ready
        .transaction { t in if isBootstrapping { t.disablesAnimations = true } }
        // Removed the subtle animation to reduce type-checking complexity
        .onAppear {
            handleOnAppear()
        }
        .onChange(of: userManager.currentUser) { _ in
            viewModel.loadCardOrderFromCloud(for: userManager.currentUser)
        }
        .onChange(of: userManager.userList) { names in
            // Skip if view model is already warm and has data
            if viewModel.isWarm && !viewModel.teamMembers.isEmpty {
                print("🚀 [WinTheDay] onChange userList - skipping fetch, already warm")
                return
            }
            viewModel.fetchMembersFromCloud { [weak viewModel] in
                viewModel?.ensureCardsForAllUsers(names)
            }
        }
        .onChange(of: viewModel.teamMembers.map { $0.id }) { _ in
            let members = viewModel.teamMembers
            if !members.isEmpty { lastNonEmptyMembers = members }
            // Only modify bootstrapping state if we're actually in a bootstrapping scenario
            if isBootstrapping && !members.isEmpty && !viewModel.isWarm {
                DispatchQueue.main.async { 
                    isBootstrapping = false
                    print("🚀 [WinTheDay] onChange teamMembers - ending bootstrap")
                }
            }
        }
        .onChange(of: viewModel.teamData.map { $0.id }) { _ in
            let data = viewModel.teamData
            if !data.isEmpty { lastNonEmptyTeamData = data }
            if enableOrderLogs { logOrder("teamData changed", data) }
            // Only modify bootstrapping state if we're actually in a bootstrapping scenario
            if isBootstrapping && !data.isEmpty && !viewModel.isWarm {
                // We have our first non-empty data frame; reveal UI without animation.
                DispatchQueue.main.async { 
                    isBootstrapping = false
                    print("🚀 [WinTheDay] onChange teamData - ending bootstrap")
                }
            }
        }
        .onChange(of: editingMemberID) { newValue in
            if newValue == nil {
                if isAwaitingDelayedReorder {
                    // Keep frozen through the delayed reorder window to avoid intermediate resort
                    if enableOrderLogs { print("🧭 [WinTheDay] Edit popup closed — keeping FROZEN during delayed reorder window") }
                } else {
                    // UNFREEZE after the edit sheet dismisses (Save or Cancel) when no delayed reorder is pending
                    if enableOrderLogs { print("🧭 [WinTheDay] Edit popup closed - UNFREEZING order") }
                    frozenOrderIDs.removeAll()
                    viewModel.isEditing = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WinTheDayManualRefresh"))) { _ in
            print("🔄 [PULL DOWN REFRESH] Starting manual refresh")
            
            // Fetch updated data from CloudKit (trophies now finalized server-side)
            viewModel.fetchMembersFromCloud {
                print("🔄 [PULL DOWN REFRESH] Data refreshed - trophy logic handled via CloudKit")
            }
            viewModel.fetchGoalNamesFromCloud()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Ensure weekly/monthly auto-resets run whenever app returns to foreground
            // Trophy finalization is now handled within performAutoResetsIfNeeded
            viewModel.performAutoResetsIfNeeded(currentDate: Date())
        }
    }
private var confettiOverlay: some View {
    Group {
        if confettiMemberID != nil {
            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(1000)
        }
    }
}

    var body: some View {
        AnyView(
            lifecycleWrapped
                .onAppear {
                    // Set initial bootstrapping state immediately when view is created
                    if viewModel.isWarm || !viewModel.teamMembers.isEmpty || !viewModel.teamData.isEmpty {
                        isBootstrapping = false
                        WinTheDayViewModel.globalIsBootstrapping = false
                        print("🚀 [WinTheDay] View created - data already available, skipping bootstrap")
                    } else {
                        print("🔄 [WinTheDay] View created - no data available, will bootstrap")
                    }
                }
                .sheet(isPresented: $emojiPickerVisible) {
                    emojiPickerSheet
                }
                .sheet(isPresented: $showProductionGoalEditor) {
                    // Existing content kept as-is
                    VStack(spacing: 20) {
                        Text("Edit Production Goals")
                            .font(.headline)
                        Stepper("Quotes Goal: \(newQuotesGoal)", value: $newQuotesGoal, in: 1...100)
                        Stepper("Sales WTD Goal: \(newSalesWTDGoal)", value: $newSalesWTDGoal, in: 1...100)
                        Stepper("Sales MTD Goal: \(newSalesMTDGoal)", value: $newSalesMTDGoal, in: 1...100)
                        HStack {
                            Button("Cancel") { showProductionGoalEditor = false }
                            Spacer()
                            Button("Save") {
                                for index in viewModel.teamMembers.indices {
                                    viewModel.teamMembers[index].quotesGoal = newQuotesGoal
                                    viewModel.teamMembers[index].salesWTDGoal = newSalesWTDGoal
                                    viewModel.teamMembers[index].salesMTDGoal = newSalesMTDGoal
                                    viewModel.saveMember(viewModel.teamMembers[index])
                                }
                                viewModel.teamMembers = viewModel.teamMembers.map { $0 }
                                showProductionGoalEditor = false
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding()
                }
                .sheet(isPresented: $showGoalNameEditor) {
                    VStack(spacing: 20) {
                        Text("Edit Goal Names")
                            .font(.headline)
                        TextField("Quotes Label", text: $editingQuotesLabel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Sales WTD Label", text: $editingSalesWTDLabel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Sales MTD Label", text: $editingSalesMTDLabel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        HStack {
                            Button("Cancel") { showGoalNameEditor = false }
                            Spacer()
                            Button("Save") {
                                viewModel.saveGoalNames(
                                    quotes: editingQuotesLabel,
                                    salesWTD: editingSalesWTDLabel,
                                    salesMTD: editingSalesMTDLabel
                                )
                                showGoalNameEditor = false
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding()
                    .onAppear {
                        editingQuotesLabel = viewModel.goalNames.quotes
                        editingSalesWTDLabel = viewModel.goalNames.salesWTD
                        editingSalesMTDLabel = viewModel.goalNames.salesMTD
                    }
                }
                // Timer cleanup no longer needed
        )
    }

@ViewBuilder
private func editingSheet(for editingID: UUID) -> some View {
    if let index = viewModel.teamMembers.firstIndex(where: { $0.id == editingID }) {
        let binding = Binding(
            get: { viewModel.teamMembers[index] },
            set: { viewModel.teamMembers[index] = $0 }
        )
        EditingOverlayView(
            member: binding,
            field: editingField,
            editingMemberID: $editingMemberID,
            recentlyCompletedIDs: $recentlyCompletedIDs,
            isAwaitingDelayedReorder: $isAwaitingDelayedReorder,
            onSave: { _, _ in
                // Save, celebrate, wait 2s, then reorder (easier for users to track)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    handleSaveAndReorder()
                }
            },
            onCelebration: { memberID, field in
                triggerCelebration(for: memberID, field: field)
            },
            onConfetti: { memberID in
                triggerConfetti(for: memberID)
            }
        )
        .environmentObject(viewModel)
    }
}

private var contentVStack: some View {
    VStack(spacing: 20) {
        header
        teamCardsList
        fallbackMessage
        Spacer()
    }
}

private var editingOverlay: some View {
    Group {
        if let editingID = editingMemberID,
           let index = viewModel.teamMembers.firstIndex(where: { $0.id == editingID }) {
            EditingOverlayView(
                member: Binding(
                    get: { viewModel.teamMembers[index] },
                    set: { viewModel.teamMembers[index] = $0 }
                ),
                field: editingField,
                editingMemberID: $editingMemberID,
                recentlyCompletedIDs: $recentlyCompletedIDs,
                isAwaitingDelayedReorder: $isAwaitingDelayedReorder,
                onSave: { _, _ in
                    // Save, celebrate, wait 2s, then reorder (easier for users to track)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        handleSaveAndReorder()
                    }
                },
                onCelebration: { memberID, field in
                    triggerCelebration(for: memberID, field: field)
                },
                onConfetti: { memberID in
                    triggerConfetti(for: memberID)
                }
            )
            .environmentObject(viewModel)
            .transition(.scale)
            .zIndex(100)
        }
    }
}

    // Function to trigger celebration animation
    private func triggerCelebration(for memberID: UUID, field: String) {
        celebrationMemberID = memberID
        celebrationField = field
        
        // Auto-hide celebration after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            celebrationMemberID = nil
            celebrationField = ""
        }
    }

    private func triggerConfetti(for memberID: UUID) {
        // Haptic feedback for goal completion
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)

        // Show full-screen confetti overlay
        confettiMemberID = memberID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            confettiMemberID = nil
        }
    }

private var winTheDayBackground: some View {
    backgroundLayer
}

// Removed winTheDayEditingOverlay and editingOverlay

// Split out onAppear logic for clarity and compile speed


private var header: some View {
    HStack {
        Text("Win the Day")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
        Menu {
            Button("Edit Goal Names") {
                showGoalNameEditor = true
            }
            Button("Edit Production Goals") {
                showProductionGoalEditor = true
            }
            Divider()
            Button(action: shareWinTheDay) {
                Label("Share Progress", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive, action: resetValues) {
                Label("Reset", systemImage: "trash.fill")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title2)
        }
    }
    .padding(.horizontal, 20)
    .padding(.top, topContentPadding)
}

private var topContentPadding: CGFloat {
    max(currentSafeAreaInsets.top - 28, 16)
}

private var currentSafeAreaInsets: UIEdgeInsets {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
        return .zero
    }

    if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
        return keyWindow.safeAreaInsets
    }

    return windowScene.windows.first?.safeAreaInsets ?? .zero
}


private var teamCardsList: some View {
    TeamCardsListView(
        viewModel: viewModel,
        teamMembers: $viewModel.teamMembers,
        teamData: $viewModel.teamData,
        lastNonEmptyTeamData: $lastNonEmptyTeamData,
        currentUser: userManager.currentUser,
        goalNames: (quotes: viewModel.goalNames.quotes, salesWTD: viewModel.goalNames.salesWTD, salesMTD: viewModel.goalNames.salesMTD),
        editingMemberID: $editingMemberID,
        editingField: $editingField,
        emojiPickerVisible: $emojiPickerVisible,
        emojiEditingID: $emojiEditingID,
        recentlyCompletedIDs: $recentlyCompletedIDs,
        celebrationMemberID: $celebrationMemberID,
        celebrationField: $celebrationField,
        confettiMemberID: $confettiMemberID,
        splashOrder: userManager.userList,
        // Keep list frozen whenever editing is active, manually frozen, or in delayed-reorder window
        isEditing: (viewModel.isEditing || editingMemberID != nil || isAwaitingDelayedReorder),
        frozenOrderIDs: frozenOrderIDs,
        freezeNow: { ids in
            // Freeze immediately at tap time to avoid any mid-frame resort
            frozenOrderIDs = ids
            viewModel.isEditing = true
            if enableOrderLogs {
                let base = viewModel.teamData.isEmpty ? lastNonEmptyTeamData : viewModel.teamData
                let names = base.map { $0.name }.joined(separator: ", ")
                print("🧭 [WinTheDay] FREEZE at tap -> [\(names)]")
            }
        },
        isPerformingAnimatedReorder: $isPerformingAnimatedReorder
    )
}



private var fallbackMessage: some View {
    Group {
        if (viewModel.teamData.isEmpty ? lastNonEmptyTeamData : viewModel.teamData).isEmpty {
            EmptyView()
        }
    }
}

private var backgroundLayer: some View {
    ZStack {
        backgroundGradient(for: viewModel.teamMembers.isEmpty ? lastNonEmptyMembers : viewModel.teamMembers).ignoresSafeArea()

        // Existing shimmer overlay (suppressed during bootstrap)
        if !isBootstrapping {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.10),
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

        // Restored true shimmer beam overlay (diagonal, plusLighter blend)
        if !isBootstrapping {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 300)
            .offset(x: shimmerPosition * UIScreen.main.bounds.width)
            .rotationEffect(.degrees(25))
            .blendMode(.plusLighter)
            .ignoresSafeArea()
        }
    }
}

// Removed editingOverlayContent, editingOverlayBody, and editingOverlay

private var emojiPickerSheet: some View {
    AnyView(
        VStack(spacing: 20) {
            Text("Choose Your Emoji").font(.headline)
            emojiGrid
            Button("Cancel") {
                emojiPickerVisible = false
            }
        }
        .padding()
    )
}


private var emojiGrid: some View {
    let emojis = [
        "👨🏽‍🦲", "👨🏾‍🦲", "👨🏿‍🦲",
        "😐", "🙂", "😊", "😌", "😎", "🤓",
        "😏", "😶", "🙃", "😬", "🤔", "😯",
        "🤨", "😄", "😅", "😇", "😍", "🤩",
        "🏃🏽‍♀️", "🏃🏾‍♀️", "🏃🏿‍♀️",
        "🏃🏽‍♂️", "🏃🏾‍♂️", "🏃🏿‍♂️",
        "🧔🏽", "🧔🏾", "🧔🏿",
        "👩🏽", "👩🏾", "👩🏿",
        "🧑🏽", "🧑🏾", "🧑🏿",
        "👨🏽", "👨🏾", "👨🏿",
        "👩🏽‍🦱", "👩🏾‍🦱", "👩🏿‍🦱",
        "👨🏽‍🦱", "👨🏾‍🦱", "👨🏿‍🦱",
        "👦🏾", "👧🏾", "👴🏾",
        "🤗", "🤝", "🫶🏾", "🙏🏾", "🤜🏾", "🤛🏾",
        "😤", "😠", "😡", "🥹", "😢", "😭"
    ]

    let columns = Array(repeating: GridItem(.flexible()), count: 6)

    return ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(emojis, id: \.self) { emoji in
                Button(action: {
                    if let id = emojiEditingID,
                       let index = viewModel.teamMembers.firstIndex(where: { $0.id == id }) {
                        viewModel.teamMembers[index].emoji = emoji
                        viewModel.teamMembers[index].emojiUserSet = true
                        viewModel.updateEmoji(for: viewModel.teamMembers[index])
                        viewModel.teamMembers = viewModel.teamMembers.map { $0 }
                    }
                    emojiPickerVisible = false
                }) {
                    Text(emoji)
                        .font(.system(size: 32))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 10)
    }
}

/// Handles saving edits and reordering cards with animation.
private func handleSaveAndReorder() {
    if enableOrderLogs {
        let before = viewModel.teamMembers
        logOrder("before SAVE+REORDER", before)
    }
    
    // Only reorder if we're not already in the correct order
    // This prevents unnecessary shuffling when the order hasn't actually changed
    let currentOrder = viewModel.teamMembers.map { $0.id }
    let expectedOrder = viewModel.teamMembers.sorted(by: viewModel.stableByScoreThenIndex).map { $0.id }
    
    let needsReordering = currentOrder != expectedOrder
    let reorderAnimation: Animation = UIAccessibility.isReduceMotionEnabled
        ? .easeOut(duration: 0.01)
        : .bouncy(duration: 0.6)
    
    if needsReordering {
        if enableOrderLogs { print("🧭 [WinTheDay] Order changed, performing reorder with smooth animation") }
        // Exit frozen/editing so the list can animate; enter animated reorder window
        frozenOrderIDs.removeAll()
        isAwaitingDelayedReorder = false
        viewModel.isEditing = false
        isPerformingAnimatedReorder = true
        // First save the data, then reorder with playful animation (Reduce Motion respected)
        withAnimation(reorderAnimation) {
            viewModel.reorderAfterSave()
            viewModel.teamData = viewModel.teamMembers
        }
        if enableOrderLogs {
            let after = viewModel.teamMembers
            logOrder("after SAVE+REORDER", after)
        }
        viewModel.saveCardOrderToCloud(for: userManager.currentUser)
        // Force update to trigger SwiftUI redraw after reordering
        viewModel.teamMembers = viewModel.teamMembers.map { $0 }
        // End the animated reorder window after the animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isPerformingAnimatedReorder = false
        }
    } else {
        if enableOrderLogs { print("🧭 [WinTheDay] No reordering needed - order is already correct") }
        // Exit frozen/editing so the list can animate; enter animated reorder window
        frozenOrderIDs.removeAll()
        isAwaitingDelayedReorder = false
        viewModel.isEditing = false
        isPerformingAnimatedReorder = true
        // Ensure UI reflects any stat changes even if order stayed the same
        withAnimation(reorderAnimation) {
            viewModel.teamData = viewModel.teamMembers
        }
        // End the animated reorder window after the animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isPerformingAnimatedReorder = false
        }
    }
    // Nudge SwiftUI to re-evaluate dependent views
    viewModel.teamMembers = viewModel.teamMembers.map { $0 }
    viewModel.teamData = viewModel.teamData.map { $0 }
}

/// Handles the onAppear logic to avoid complex type-checking issues
private func handleOnAppear() {
    // Always set up shimmer animation regardless of bootstrap state
    shimmerPosition = -1.0
    // Start shimmer only after initial content is visible to avoid flash
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        guard !isBootstrapping else { return }
        withAnimation(Animation.linear(duration: 12).repeatForever(autoreverses: false)) {
            shimmerPosition = 1.5
        }
    }
    
    // If the view model was pre-warmed (from Splash/App), skip bootstrap and extra fetches
    if viewModel.isWarm {
        print("🚀 [WinTheDay] handleOnAppear - view model is warm, skipping bootstrap")
        didRunInitialSync = true
        isBootstrapping = false
        WinTheDayViewModel.globalIsBootstrapping = false
        
        // Run auto-resets even when warm so Sunday/Monday transitions are honored
        viewModel.performAutoResetsIfNeeded(currentDate: Date())
        
        // Trophy finalization is now handled within performAutoResetsIfNeeded
        print("🏆 [WinTheDay] handleOnAppear - trophy finalization handled in performAutoResetsIfNeeded")
        return
    }

    // If we've already synced once (e.g., user came from Splash), do not re-bootstrap.
    if didRunInitialSync {
        print("🔄 [WinTheDay] handleOnAppear - already synced once, skipping bootstrap")
        viewModel.performAutoResetsIfNeeded(currentDate: Date())
        isBootstrapping = false
        WinTheDayViewModel.globalIsBootstrapping = false
        
        // Trophy finalization is now handled within performAutoResetsIfNeeded
        print("🏆 [WinTheDay] handleOnAppear - trophy finalization handled in performAutoResetsIfNeeded")
        return
    }

    // Check if we need to bootstrap based on current state
    if !shouldBootstrap {
        print("🚀 [WinTheDay] handleOnAppear - no bootstrap needed, data already available")
        isBootstrapping = false
        WinTheDayViewModel.globalIsBootstrapping = false
        
        // Trophy finalization is now handled within performAutoResetsIfNeeded
        print("🏆 [WinTheDay] handleOnAppear - trophy finalization handled in performAutoResetsIfNeeded")
        return
    }

    // First-time appearance: enable bootstrap until initial data is ready.
    isBootstrapping = true
    WinTheDayViewModel.globalIsBootstrapping = true
    didRunInitialSync = true

    // Run auto-resets on first visit
    viewModel.performAutoResetsIfNeeded(currentDate: Date())

    viewModel.fetchGoalNamesFromCloud()
    viewModel.fetchMembersFromCloud { [weak viewModel] in
        viewModel?.ensureCardsForAllUsers(userManager.userList)
        // Trophy logic runs locally on each device using synced data
        // Reveal once we have our first stable dataset
        DispatchQueue.main.async {
            self.isBootstrapping = false
            WinTheDayViewModel.globalIsBootstrapping = false
        }
    }
    viewModel.loadCardOrderFromCloud(for: userManager.currentUser)
    
    // Trophy finalization is now handled within performAutoResetsIfNeeded
    // No need for separate scheduling since it runs on every performAutoResetsIfNeeded call
}

// MARK: - Hybrid Trophy System
// isWeeklyMet function moved to WinTheDayViewModel



// Trophy finalization is now handled in WinTheDayViewModel.performAutoResetsIfNeeded()
// This ensures trophies are finalized BEFORE the weekly reset, not after

// Trophy finalization is now handled in WinTheDayViewModel.performAutoResetsIfNeeded()
// This ensures trophies are finalized BEFORE the weekly reset, not after

// Trophy finalization is now handled within performAutoResetsIfNeeded
// No need for separate timer scheduling




    // MARK: - Share Functionality
    
    private func shareWinTheDay() {
        let image = generateShareableImage()
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            
            // For iPad, set the popover source
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func generateShareableImage() -> UIImage {
        let targetSize = CGSize(width: 400, height: 500)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Use the same dynamic background as Win the Day based on team progress
            let teamProgress = viewModel.teamMembers
            var totalActual = 0
            var totalGoal = 0
            
            for member in teamProgress {
                totalActual += member.quotesToday + member.salesWTD + member.salesMTD
                totalGoal += member.quotesGoal + member.salesWTDGoal + member.salesMTDGoal
            }
            
            let colors: [UIColor]
            if totalGoal > 0 {
                let percent = Double(totalActual) / Double(totalGoal)
                switch percent {
                case 0..<0.26:
                    colors = [UIColor.red.withAlphaComponent(0.3), UIColor.red]
                case 0.26..<0.51:
                    colors = [UIColor.orange.withAlphaComponent(0.3), UIColor.orange]
                case 0.51..<0.8:
                    colors = [UIColor.yellow.withAlphaComponent(0.3), UIColor.yellow]
                default:
                    colors = [UIColor.green.withAlphaComponent(0.0), UIColor.green]
                }
            } else {
                colors = [UIColor.gray.withAlphaComponent(0.3), UIColor.gray]
            }
            
            // Create gradient background matching Win the Day
            let cgColors = colors.map { $0.cgColor }
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors as CFArray, locations: [0.0, 1.0])!
            cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: targetSize.width, y: targetSize.height), options: [])
            
            // Header matching your app - ensure full banner is visible
            let headerRect = CGRect(x: 0, y: 0, width: targetSize.width, height: 55)
            drawAppHeader(in: headerRect, context: cgContext)
            
            // Get the actual top 3 performers based on their current scores
            let sortedMembers = viewModel.teamMembers.sorted { lhs, rhs in
                let lScore = lhs.quotesToday + lhs.salesWTD + lhs.salesMTD
                let rScore = rhs.quotesToday + rhs.salesWTD + rhs.salesMTD
                if lScore != rScore {
                    return lScore > rScore  // Higher scores first
                }
                // If scores are equal, maintain stable sort by name
                return lhs.name < rhs.name
            }
            let membersToShow = Array(sortedMembers.prefix(3))
            
            // Draw cards optimized for text preview - use extra space
            let cardStartY = headerRect.maxY + 15
            let cardHeight: CGFloat = 125
            let cardSpacing: CGFloat = 12
            
            for (index, member) in membersToShow.enumerated() {
                let cardY = cardStartY + CGFloat(index) * (cardHeight + cardSpacing)
                let cardRect = CGRect(x: 20, y: cardY, width: targetSize.width - 40, height: cardHeight)
                drawAppStyleCard(member: member, in: cardRect, context: cgContext)
            }
        }
    }
    
    private func drawAppHeader(in rect: CGRect, context: CGContext) {
        // Blue gradient header with "TOP PERFORMERS" banner
        let colors = [UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0).cgColor,
                      UIColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1.0).cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: rect.height), options: [])
        
        // Title with trophy
        let titleText = "🏆 TOP PERFORMERS"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateText = dateFormatter.string(from: Date())
        let subtitleText = "Win the Day • \(dateText)"
        
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: UIColor.white
        ]
        
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8)
        ]
        
        let titleSize = titleText.size(withAttributes: titleAttributes)
        let subtitleSize = subtitleText.size(withAttributes: subtitleAttributes)
        
        let titleRect = CGRect(
            x: rect.midX - titleSize.width / 2,
            y: 12,
            width: titleSize.width,
            height: titleSize.height
        )
        
        let subtitleRect = CGRect(
            x: rect.midX - subtitleSize.width / 2,
            y: titleRect.maxY + 2,
            width: subtitleSize.width,
            height: subtitleSize.height
        )
        
        titleText.draw(in: titleRect, withAttributes: titleAttributes)
        subtitleText.draw(in: subtitleRect, withAttributes: subtitleAttributes)
    }
    
    private func drawAppStyleCard(member: TeamMember, in rect: CGRect, context: CGContext) {
        // Card background with rounded corners and shadow (matching your app)
        let cardRect = rect
        context.setFillColor(UIColor.systemBackground.cgColor)
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 2, color: UIColor.black.withAlphaComponent(0.1).cgColor)
        
        // Draw rounded rectangle for card background
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 12)
        context.addPath(path.cgPath)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Add white border to match Win the Day cards
        let borderPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 12)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(6.0)
        context.addPath(borderPath.cgPath)
        context.strokePath()
        
        // Red header section - compact for text preview
        let headerHeight: CGFloat = 40
        let headerRect = CGRect(x: cardRect.minX, y: cardRect.minY, width: cardRect.width, height: headerHeight)
        let headerPath = UIBezierPath(roundedRect: headerRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 12, height: 12))
        context.setFillColor(UIColor(red: 237/255, green: 29/255, blue: 36/255, alpha: 1.0).cgColor)
        context.addPath(headerPath.cgPath)
        context.fillPath()
        
        // Emoji and name in header with larger fonts
        let emojiText = member.emoji
        let nameText = member.name
        let emojiAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24)]
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: UIColor.white
        ]
        
        let emojiSize = emojiText.size(withAttributes: emojiAttributes)
        let nameSize = nameText.size(withAttributes: nameAttributes)
        
        let emojiRect = CGRect(x: headerRect.minX + 10, y: headerRect.midY - emojiSize.height/2, width: emojiSize.width, height: emojiSize.height)
        let nameRect = CGRect(x: emojiRect.maxX + 8, y: headerRect.midY - nameSize.height/2, width: nameSize.width, height: nameSize.height)
        
        emojiText.draw(in: emojiRect, withAttributes: emojiAttributes)
        nameText.draw(in: nameRect, withAttributes: nameAttributes)
        
        // Trophy count on the right side of header with larger font
        let trophyCount = getTrophyCount(for: member)
        if trophyCount > 0 {
            let trophyText = String(repeating: "🏆", count: trophyCount)
            let trophyAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20)]
            let trophySize = trophyText.size(withAttributes: trophyAttributes)
            let trophyRect = CGRect(x: headerRect.maxX - trophySize.width - 10, y: headerRect.midY - trophySize.height/2, width: trophySize.width, height: trophySize.height)
            trophyText.draw(in: trophyRect, withAttributes: trophyAttributes)
        }
        
        // Progress rows in white content area - optimized spacing
        let contentStartY = headerRect.maxY + 8
        let rowSpacing: CGFloat = 24  // Slightly increased spacing
        
        let progressItems: [(value: Int, goal: Int, label: String, type: StatType)] = [
            (member.quotesToday, member.quotesGoal, viewModel.goalNames.quotes, .quotes),
            (member.salesWTD, member.salesWTDGoal, viewModel.goalNames.salesWTD, .salesWTD),
            (member.salesMTD, member.salesMTDGoal, viewModel.goalNames.salesMTD, .salesMTD)
        ]
        
        for (index, item) in progressItems.enumerated() {
            let progressY = contentStartY + CGFloat(index) * rowSpacing
            drawAppStyleProgressRow(
                value: item.value,
                goal: item.goal,
                label: item.label,
                type: item.type,
                in: CGRect(
                    x: cardRect.minX + 12,
                    y: progressY,
                    width: cardRect.width - 24,
                    height: 24
                ),
                context: context
            )
        }
    }
    
    private func drawAppStyleProgressRow(value: Int, goal: Int, label: String, type: StatType, in rect: CGRect, context: CGContext) {
        // Label on the left with larger font
        let labelText = label
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]
        let labelSize = labelText.size(withAttributes: labelAttributes)
        let labelRect = CGRect(x: rect.minX, y: rect.midY - labelSize.height/2, width: labelSize.width, height: labelSize.height)
        labelText.draw(in: labelRect, withAttributes: labelAttributes)
        
        // Progress bar positioned correctly to match your app
        let barWidth: CGFloat = 140
        let barHeight: CGFloat = 10
        let barX = rect.maxX - barWidth - 80
        let barY = rect.midY - barHeight/2
        let barRect = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
        
        // Background bar with rounded rectangle (not oval)
        let backgroundPath = UIBezierPath(roundedRect: barRect, cornerRadius: barHeight/2)
        context.setFillColor(UIColor.systemGray5.cgColor)
        context.addPath(backgroundPath.cgPath)
        context.fillPath()
        
        // Progress fill with rounded rectangle
        let progress = goal > 0 ? min(CGFloat(value) / CGFloat(goal), 1.0) : 0
        let fillWidth = barWidth * progress
        
        if fillWidth > 0 {
            let fillRect = CGRect(x: barX, y: barY, width: fillWidth, height: barHeight)
            let fillPath = UIBezierPath(roundedRect: fillRect, cornerRadius: barHeight/2)
            let progressColor = getProgressColor(for: type, value: value, goal: goal)
            context.setFillColor(progressColor.cgColor)
            context.addPath(fillPath.cgPath)
            context.fillPath()
        }
        
        // Value on the right with larger font
        let valueText = "\(value) / \(goal)"
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]
        let valueSize = valueText.size(withAttributes: valueAttributes)
        let valueRect = CGRect(x: rect.maxX - valueSize.width, y: rect.midY - valueSize.height/2, width: valueSize.width, height: valueSize.height)
        valueText.draw(in: valueRect, withAttributes: valueAttributes)
    }
    
    private func getProgressColor(for type: StatType, value: Int, goal: Int) -> UIColor {
        guard goal > 0 else { return UIColor.systemGray }

        let calendar = Calendar.current
        let today = Date()

        let isOnTrack: Bool
        switch type {
        case .quotes, .salesWTD:
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let expected = Double(goal) * Double(dayOfWeek) / 7.0
            isOnTrack = Double(value) >= expected
        case .salesMTD:
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let expected = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            isOnTrack = Double(value) >= expected
        }

        return isOnTrack ? UIColor.systemGreen : UIColor.systemYellow
    }
    
    private func getTrophyCount(for member: TeamMember) -> Int {
        let quotesHit = member.quotesGoal > 0 && member.quotesToday >= member.quotesGoal
        let salesHit = member.salesWTDGoal > 0 && member.salesWTD >= member.salesWTDGoal
        let currentWeekProgress = (quotesHit || salesHit) ? 1 : 0
        return member.trophyStreakCount + currentWeekProgress
    }
    

    // Reset function to reset values
    private func resetValues() {
        for index in viewModel.teamMembers.indices {
            // Only reset Win The Day specific progress values
            // Preserve Life Scoreboard fields (score, pending, projected, actual)
            viewModel.teamMembers[index].quotesToday = 0
            viewModel.teamMembers[index].salesWTD = 0
            viewModel.teamMembers[index].salesMTD = 0
            
            // Reset goals to default values
            viewModel.teamMembers[index].quotesGoal = 10
            viewModel.teamMembers[index].salesWTDGoal = 2
            viewModel.teamMembers[index].salesMTDGoal = 6
            
            print("🔁 Resetting Win The Day values for \(viewModel.teamMembers[index].name): Quotes Goal = \(viewModel.teamMembers[index].quotesGoal), WTD Goal = \(viewModel.teamMembers[index].salesWTDGoal), MTD Goal = \(viewModel.teamMembers[index].salesMTDGoal)")
            
            // Save only the Win The Day fields to avoid affecting Life Scoreboard data
            viewModel.saveWinTheDayFields(viewModel.teamMembers[index])
        }
        // Force update to trigger SwiftUI redraw
        viewModel.teamMembers = viewModel.teamMembers.map { $0 }
    }

    // New background gradient based on team progress
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
        case 0..<0.26:
            colors = [Color.red.opacity(0.3), Color.red]
        case 0.26..<0.51:
            colors = [Color.orange.opacity(0.3), Color.orange]
        case 0.51..<0.8:
            colors = [Color.yellow.opacity(0.3), Color.yellow]
        default:
            colors = [Color.green.opacity(0.0), Color.green]
        }

        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func progressColor(for type: StatType, value: Int, goal: Int) -> Color {
        guard goal > 0 else { return .gray }

        let calendar = Calendar.current
        let today = Date()

        let isOnTrack: Bool

        switch type {
        case .quotes, .salesWTD:
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let expected = Double(goal) * Double(dayOfWeek) / 7.0
            isOnTrack = Double(value) >= expected

        case .salesMTD:
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let expected = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            isOnTrack = Double(value) >= expected
        }

        return isOnTrack ? .green : .yellow
    }
}

// MARK: - StatRow View
struct StatRow: View {
    let title: String
    let value: Int
    let goal: Int
    let type: StatType
    let isEditable: Bool
    @Binding var member: TeamMember
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var teamData: [TeamMember]
    let onTap: () -> Void

    var body: some View {
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
                    .fill(progressColor(for: type, value: value, goal: goal))
                    .frame(
                        width: goal > 0 ? min(CGFloat(value) / CGFloat(goal), 1.0) * 140 : 0,
                        height: 10
                    )
                    .padding(.leading, 10)
            }

            Text("\(value) / \(goal)")
                .font(.subheadline.bold())
                .foregroundColor(.primary)
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
        .opacity(1.0)
        .onChange(of: value) { newValue in
            let oldColor = progressColor(for: type, value: newValue - 1, goal: goal)
            let newColor = progressColor(for: type, value: newValue, goal: goal)
            if oldColor != .green && newColor == .green {
                recentlyCompletedIDs.insert(member.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    recentlyCompletedIDs.remove(member.id)
                }
            }
        }
    }

    private func progressColor(for type: StatType, value: Int, goal: Int) -> Color {
        guard goal > 0 else { return .gray }

        let calendar = Calendar.current
        let today = Date()

        let isOnTrack: Bool
        switch type {
        case .quotes, .salesWTD:
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let expected = Double(goal) * Double(dayOfWeek) / 7.0
            isOnTrack = Double(value) >= expected
        case .salesMTD:
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let expected = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            isOnTrack = Double(value) >= expected
        }

        return isOnTrack ? .green : .yellow
    }
}


extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}


    // Helper: Get value for a stat title and member
    private func valueFor(_ title: String, of member: TeamMember) -> Int {
        switch title {
        case "Quotes Today", "Quotes WTD": return member.quotesToday
        case "Sales WTD": return member.salesWTD
        case "Sales MTD": return member.salesMTD
        default: return 0
        }
    }

    // Helper: Get goal for a stat title and member
    private func goalFor(_ title: String, of member: TeamMember) -> Int {
        switch title {
        case "Quotes Today", "Quotes WTD": return member.quotesGoal
        case "Sales WTD": return member.salesWTDGoal
        case "Sales MTD": return member.salesMTDGoal
        default: return 0
        }
    }
    




// MARK: - FieldStepperRow
private struct FieldStepperRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label)
            Stepper(value: $value, in: 0...1000) {
                Text("\(value)")
            }
        }
    }
}

// MARK: - EditingOverlayView
private struct EditingOverlayView: View {
    @EnvironmentObject var viewModel: WinTheDayViewModel
    @Binding var member: TeamMember
    let field: String
    @Binding var editingMemberID: UUID?
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var isAwaitingDelayedReorder: Bool
    let onSave: ((UUID?, String) -> Void)?
    let onCelebration: ((UUID, String) -> Void)?
    let onConfetti: ((UUID) -> Void)?
    @State private var oldQuotesValue: Int = 0
    @State private var oldSalesWTDValue: Int = 0
    @State private var oldSalesMTDValue: Int = 0

    var body: some View {
        bodyContent
    }

    private var bodyContent: some View {
        VStack(spacing: 15) {
            fieldStepper
            buttonRow
        }
        .padding()
        .frame(width: 280)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(radius: 8)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.4)))
        .onAppear {
            // Store ALL old values when editing starts
            oldQuotesValue = member.quotesToday
            oldSalesWTDValue = member.salesWTD
            oldSalesMTDValue = member.salesMTD
        }
    }

    private var buttonRow: some View {
        HStack {
            Button("Cancel") {
                // Restore original values when canceling
                member.quotesToday = oldQuotesValue
                member.salesWTD = oldSalesWTDValue
                member.salesMTD = oldSalesMTDValue
                editingMemberID = nil
                // Don't trigger any reordering when canceling
            }
            Spacer()
            Button("Save") {
                // Mark that we are entering the delayed-reorder window BEFORE dismissing the editor
                isAwaitingDelayedReorder = true
                let capturedID = editingMemberID
                let capturedField = field
                editingMemberID = nil // ✅ Dismiss immediately (after flag set)

                // Only trigger reordering if values actually changed
                let valuesChanged = (member.quotesToday != oldQuotesValue) ||
                                   (member.salesWTD != oldSalesWTDValue) ||
                                   (member.salesMTD != oldSalesMTDValue)
                if valuesChanged {

                    viewModel.saveWinTheDayFields(member)
                    onSave?(capturedID, capturedField)
                    let shouldCelebrate = checkIfAnyProgressTurnedGreen()
                    let didCompleteAnyGoal = checkIfAnyGoalCompleted()
                    
                    if shouldCelebrate {
                        onCelebration?(member.id, "any") // 🎉 small burst
                    }
                    if didCompleteAnyGoal {
                        onConfetti?(member.id)           // 🎊 confetti big celebration
                    }
                } else {

                }
            }
        }
    }

    // MARK: - Field stepper using FieldStepperRow
    @ViewBuilder
    private var fieldStepper: some View {
        FieldStepperRow(label: "Quotes WTD", value: $member.quotesToday)
        FieldStepperRow(label: "Sales WTD", value: $member.salesWTD)
        FieldStepperRow(label: "Sales MTD", value: $member.salesMTD)
    }
    
    // Helper functions to check progress color changes
    private func getCurrentValue(for field: String, member: TeamMember) -> Int {
        switch field {
        case "quotesToday": return member.quotesToday
        case "salesWTD": return member.salesWTD
        case "salesMTD": return member.salesMTD
        default: return 0
        }
    }
    
    private func getGoal(for field: String, member: TeamMember) -> Int {
        switch field {
        case "quotesToday": return member.quotesGoal
        case "salesWTD": return member.salesWTDGoal
        case "salesMTD": return member.salesMTDGoal
        default: return 0
        }
    }
    
    // Check if ANY of the three progress lines turned green
    private func checkIfAnyProgressTurnedGreen() -> Bool {
        // Check quotes progress
        let oldQuotesColor = progressColor(for: "quotesToday", value: oldQuotesValue, goal: member.quotesGoal)
        let newQuotesColor = progressColor(for: "quotesToday", value: member.quotesToday, goal: member.quotesGoal)
        let quotesTurnedGreen = oldQuotesColor != .green && newQuotesColor == .green
        
        // Check sales WTD progress
        let oldSalesWTDColor = progressColor(for: "salesWTD", value: oldSalesWTDValue, goal: member.salesWTDGoal)
        let newSalesWTDColor = progressColor(for: "salesWTD", value: member.salesWTD, goal: member.salesWTDGoal)
        let salesWTDTurnedGreen = oldSalesWTDColor != .green && newSalesWTDColor == .green
        
        // Check sales MTD progress
        let oldSalesMTDColor = progressColor(for: "salesMTD", value: oldSalesMTDValue, goal: member.salesMTDGoal)
        let newSalesMTDColor = progressColor(for: "salesMTD", value: member.salesMTD, goal: member.salesMTDGoal)
        let salesMTDTurnedGreen = oldSalesMTDColor != .green && newSalesMTDColor == .green
        
        // Return true if ANY line turned green
        return quotesTurnedGreen || salesWTDTurnedGreen || salesMTDTurnedGreen
    }
    
    private func checkIfAnyGoalCompleted() -> Bool {
        let quotesCompleted   = (oldQuotesValue < member.quotesGoal)   && (member.quotesToday >= member.quotesGoal)
        let salesWTDCompleted = (oldSalesWTDValue < member.salesWTDGoal) && (member.salesWTD >= member.salesWTDGoal)
        let salesMTDCompleted = (oldSalesMTDValue < member.salesMTDGoal) && (member.salesMTD >= member.salesMTDGoal)
        return quotesCompleted || salesWTDCompleted || salesMTDCompleted
    }
    
    private func progressColor(for field: String, value: Int, goal: Int) -> Color {
        guard goal > 0 else { return .gray }
        
        let calendar = Calendar.current
        let today = Date()
        
        let isOnTrack: Bool
        switch field {
        case "quotesToday", "salesWTD":
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let expected = Double(goal) * Double(dayOfWeek) / 7.0
            isOnTrack = Double(value) >= expected
        case "salesMTD":
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let expected = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            isOnTrack = Double(value) >= expected
        default:
            isOnTrack = false
        }
        
        return isOnTrack ? .green : .yellow
    }
}


private struct TeamMemberCardView: View {
    @Binding var member: TeamMember
    let isEditable: Bool
    let selectedUserName: String
    let onEdit: (String) -> Void
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var teamData: [TeamMember]
    let quotesLabel: String
    let salesWTDLabel: String
    let salesMTDLabel: String
    @Binding var celebrationMemberID: UUID?
    @Binding var celebrationField: String
    @Binding var confettiMemberID: UUID?
    let trophyCount: Int

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    if isEditable {
                        Button(action: { onEdit("emoji") }) {
                            Text(member.emoji)
                                .font(.title2.bold())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu { }
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
                    Spacer()
                    // Far-right trophy row (right-justified, grows leftward)
                    TrophyRowView(count: trophyCount)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 237/255, green: 29/255, blue: 36/255))
                .foregroundColor(.white)
                .cornerRadius(10, corners: [.topLeft, .topRight])

                StatRow(
                    title: quotesLabel,
                    value: member.quotesToday,
                    goal: member.quotesGoal,
                    type: .quotes,
                    isEditable: isEditable,
                    member: $member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $teamData,
                    onTap: { if isEditable { onEdit("quotesToday") } }
                )
                StatRow(
                    title: salesWTDLabel,
                    value: member.salesWTD,
                    goal: member.salesWTDGoal,
                    type: .salesWTD,
                    isEditable: isEditable,
                    member: $member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $teamData,
                    onTap: { if isEditable { onEdit("salesWTD") } }
                )
                StatRow(
                    title: salesMTDLabel,
                    value: member.salesMTD,
                    goal: member.salesMTDGoal,
                    type: .salesMTD,
                    isEditable: isEditable,
                    member: $member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $teamData,
                    onTap: { if isEditable { onEdit("salesMTD") } }
                )
            }
            .padding(6)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 0)
            
            // Celebration overlay - only show if this is the celebrating member
            if celebrationMemberID == member.id {
                CelebrationView(field: celebrationField)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Celebration View
struct CelebrationView: View {
    let field: String
    @State private var scale: CGFloat = 0.0
    @State private var opacity: Double = 0.0
    
    var body: some View {
        VStack {
            Spacer()
            Text("🎉")
                .font(.system(size: 60))
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    // Start animation sequence
                    withAnimation(.easeOut(duration: 0.3)) {
                        scale = 1.2
                        opacity = 1.0
                    }
                    
                    // Scale down to normal size
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = 1.0
                        }
                    }
                    
                    // Fade out
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeIn(duration: 0.3)) {
                            opacity = 0.0
                        }
                    }
                }
            Spacer()
        }
    }
}

// MARK: - Confetti View (CAEmitterLayer-backed)
struct ConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false

        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterMode = .surface
        emitter.emitterSize = CGSize(width: UIScreen.main.bounds.width, height: 1)
        emitter.emitterPosition = CGPoint(x: UIScreen.main.bounds.width/2, y: -8) // from top
        emitter.birthRate = 1

        let colors: [UIColor] = [
            UIColor(red: 0.95, green: 0.30, blue: 0.36, alpha: 1.0), // red
            UIColor(red: 1.00, green: 0.70, blue: 0.20, alpha: 1.0), // orange
            UIColor(red: 1.00, green: 0.90, blue: 0.30, alpha: 1.0), // yellow
            UIColor(red: 0.20, green: 0.75, blue: 0.35, alpha: 1.0), // green
            UIColor(red: 0.25, green: 0.60, blue: 0.95, alpha: 1.0), // blue
            UIColor(red: 0.60, green: 0.40, blue: 0.95, alpha: 1.0)  // purple
        ]

        let shapes: [CGPath] = [
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 6, height: 9), cornerRadius: 2).cgPath, // rectangle (smaller)
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 6, height: 6)).cgPath,                         // circle (smaller)
            ConfettiView.starPath(size: 8).cgPath                                                        // star (smaller)
        ]

        var cells: [CAEmitterCell] = []
        for color in colors {
            for shape in shapes {
                let cell = CAEmitterCell()
                cell.birthRate = 18
                cell.lifetime = 4.0
                cell.lifetimeRange = 1.0
                cell.velocity = 140
                cell.velocityRange = 60
                cell.emissionLongitude = .pi
                cell.emissionRange = .pi / 8
                cell.spin = 3.5
                cell.spinRange = 4.0
                cell.scale = 0.5
                cell.scaleRange = 0.2
                cell.yAcceleration = 180
                cell.xAcceleration = 10
                cell.alphaRange = 0.0
                cell.alphaSpeed = -0.35
                cell.color = color.cgColor
                cell.contents = ConfettiView.image(for: shape, color: color).cgImage
                cells.append(cell)
            }
        }

        emitter.emitterCells = cells
        view.layer.addSublayer(emitter)

        // Short celebratory burst, then let pieces fall out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            emitter.birthRate = 0
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { }

    // Build images for cells
    private static func image(for path: CGPath, color: UIColor) -> UIImage {
        let bounds = path.boundingBoxOfPath.insetBy(dx: -2, dy: -2)
        let size = CGSize(width: max(12, bounds.width), height: max(12, bounds.height))
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return UIImage() }
        ctx.translateBy(x: (size.width - bounds.width)/2 - bounds.origin.x,
                        y: (size.height - bounds.height)/2 - bounds.origin.y)
        ctx.addPath(path)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }

    private static func starPath(size: CGFloat, points: Int = 5) -> UIBezierPath {
        let path = UIBezierPath()
        let center = CGPoint(x: size/2, y: size/2)
        let outer = size/2
        let inner = outer * 0.5
        var angle: CGFloat = -.pi/2
        let step = .pi / CGFloat(points)
        var isOuter = true
        for _ in 0..<(points * 2) {
            let r = isOuter ? outer : inner
            let pt = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if path.isEmpty { path.move(to: pt) } else { path.addLine(to: pt) }
            isOuter.toggle()
            angle += step
        }
        path.close()
        return path
    }
}
    

// MARK: - Extracted Team Cards List (lighter for the type checker)
private struct TeamCardsListView: View {
    @ObservedObject var viewModel: WinTheDayViewModel
    @Binding var teamMembers: [TeamMember]
    @Binding var teamData: [TeamMember]
    @Binding var lastNonEmptyTeamData: [TeamMember]
    let currentUser: String
    let goalNames: (quotes: String, salesWTD: String, salesMTD: String)
    @Binding var editingMemberID: UUID?
    @Binding var editingField: String
    @Binding var emojiPickerVisible: Bool
    @Binding var emojiEditingID: UUID?
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var celebrationMemberID: UUID?
    @Binding var celebrationField: String
    @Binding var confettiMemberID: UUID?
    let splashOrder: [String]
    let isEditing: Bool
    let frozenOrderIDs: [UUID]
    let freezeNow: ([UUID]) -> Void
    @Binding var isPerformingAnimatedReorder: Bool
    @State private var cachedOrderIDs: [UUID] = []
    @State private var snapshotIDs: [UUID] = []

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(dataSource, id: \.id) { member in
                        if let idx = teamMembers.firstIndex(where: { $0.name == member.name }) {
                            let isEditable = teamMembers[idx].name == currentUser
                            TeamMemberCardView(
                                member: $teamMembers[idx],
                                isEditable: isEditable,
                                selectedUserName: currentUser,
                                onEdit: { field in
                                    guard isEditable else { return }

                                    // Freeze immediately using the exact on-screen order to prevent any movement
                                    freezeNow(dataSource.map { $0.id })
                                    // Now proceed to open the editor
                                    editingMemberID = member.id
                                    editingField = field
                                    if field == "emoji" {
                                        emojiPickerVisible = true
                                        emojiEditingID = member.id
                                        editingMemberID = nil
                                    } else {
                                        withAnimation { scrollProxy.scrollTo(member.id, anchor: .center) }
                                    }
                                },
                                recentlyCompletedIDs: $recentlyCompletedIDs,
                                teamData: $teamData,
                                quotesLabel: goalNames.quotes,
                                salesWTDLabel: goalNames.salesWTD,
                                salesMTDLabel: goalNames.salesMTD,
                                celebrationMemberID: $celebrationMemberID,
                                celebrationField: $celebrationField,
                                confettiMemberID: $confettiMemberID,
                                trophyCount: {
                                    let quotesHit = member.quotesGoal > 0 && member.quotesToday >= member.quotesGoal
                                    let salesHit = member.salesWTDGoal > 0 && member.salesWTD >= member.salesWTDGoal
                                    let currentWeekProgress = (quotesHit || salesHit) ? 1 : 0
                                    return member.trophyStreakCount + currentWeekProgress
                                }()
                            )
                            .id(member.id)
                        }
                    }
                }
                .animation({ () -> Animation? in
                    if WinTheDayViewModel.globalIsBootstrapping { return nil }
                    if isPerformingAnimatedReorder {
                        return UIAccessibility.isReduceMotionEnabled ? .easeOut(duration: 0.01) : .bouncy(duration: 0.6)
                    }
                    if !isEditing && frozenOrderIDs.isEmpty && cachedOrderIDs.isEmpty {
                        return .easeInOut(duration: 0.3)
                    }
                    return nil
                }(), value: dataSource.map { $0.id })
                .id("cards-container")
                .padding(.horizontal, 20)
            }
            .transaction { t in
                if (isEditing || !cachedOrderIDs.isEmpty || !frozenOrderIDs.isEmpty) && !isPerformingAnimatedReorder {
                    t.disablesAnimations = true
                }
            }
            .refreshable {
                NotificationCenter.default.post(name: .init("WinTheDayManualRefresh"), object: nil)
            }
            .onChange(of: isEditing) { newValue in
                if newValue {
                    // Capture the exact on-screen order at the moment editing begins
                    let base = teamData.isEmpty ? lastNonEmptyTeamData : teamData
                    cachedOrderIDs = base.map { $0.id }
                    snapshotIDs = cachedOrderIDs
                } else {
                    cachedOrderIDs.removeAll()
                    snapshotIDs.removeAll()
                }
            }
            .onChange(of: frozenOrderIDs) { ids in
                if !ids.isEmpty {
                    snapshotIDs = ids
                }
            }
        }
    }

    private var dataSource: [TeamMember] {
        let base = teamData.isEmpty ? lastNonEmptyTeamData : teamData



        // NEW: While editing, always render strictly from a snapshot order, never live resorting
        if isEditing || !frozenOrderIDs.isEmpty {
            // Choose the most stable order source available while editing
            let ids: [UUID]
            if !frozenOrderIDs.isEmpty {
                ids = frozenOrderIDs
            } else if !snapshotIDs.isEmpty {
                ids = snapshotIDs
            } else if !cachedOrderIDs.isEmpty {
                ids = cachedOrderIDs
            } else {
                // Last resort – keep whatever is currently on screen without re-sorting
                let base = teamData.isEmpty ? lastNonEmptyTeamData : teamData
                ids = base.map { $0.id }
            }

            // Render by mapping snapshot IDs to the current teamMembers (live values, fixed order)
            let ordered = ids.compactMap { id in
                teamMembers.first(where: { $0.id == id }) ?? teamData.first(where: { $0.id == id })
            }

            return ordered
        }

        // During the animated reorder window, use normal live ordering so it can animate
        if isPerformingAnimatedReorder {
            return liveOrdered(base: base)
        }

        // Only apply normal ordering logic when NOT editing
        return liveOrdered(base: base)
    }

    private func liveOrdered(base: [TeamMember]) -> [TeamMember] {
        // Build a fast index map for Splash order
        let indexMap: [String:Int] = Dictionary(uniqueKeysWithValues: splashOrder.enumerated().map { ($1, $0) })

        // Split into members with any progress and those with zero progress
        let withProgress = base.filter { ($0.quotesToday + $0.salesWTD + $0.salesMTD) > 0 }
        let zeroProgress = base.filter { ($0.quotesToday + $0.salesWTD + $0.salesMTD) == 0 }

        if withProgress.isEmpty {

            return zeroProgress.sorted { (indexMap[$0.name] ?? Int.max) < (indexMap[$1.name] ?? Int.max) }
        } else {
            let sortedProgress = withProgress.sorted { lhs, rhs in
                let l = lhs.quotesToday + lhs.salesWTD + lhs.salesMTD
                let r = rhs.quotesToday + rhs.salesWTD + rhs.salesMTD
                if l == r {
                    return (indexMap[lhs.name] ?? Int.max) < (indexMap[rhs.name] ?? Int.max)
                }
                return l > r
            }
            let sortedZeros = zeroProgress.sorted { (indexMap[$0.name] ?? Int.max) < (indexMap[$1.name] ?? Int.max) }

            return sortedProgress + sortedZeros
        }
    }
    
}
