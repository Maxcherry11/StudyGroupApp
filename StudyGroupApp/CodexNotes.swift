// Codex Project Rules & Constraints
// ----------------------------------
// ✅ Target iOS 15.6 — Do NOT use iOS 16+ APIs.
// ✅ Use NavigationView instead of NavigationStack.
// ✅ Support iPhone screens first (mobile-first design).
// ✅ Avoid Charts, Grid, and other iOS 16+ views.
// ✅ Keep layout simple, clean, and follow Apple’s Human Interface Guidelines.
// ✅ CloudKit must work offline and sync cleanly when iCloud is available.
// ✅ Do not hardcode logic based on goal names — use IDs or model structure.
// ✅ Emoji must sync using CloudKit.
// ✅ Visual polish is complete — do not alter animations or card layout unless requested.
// ✅ Confetti appears only when full goals are met, not partial.
// ✅ Splash screen must allow user selection (DJ, Ron, Deanna, Dimitri) and lock fields for others.
// ✅ Life Scoreboard and Win the Day must support dynamic updates from UI.
//
// Codex File Placement Rules
// --------------------------
// ✅ All new files must be saved in the main StudyGroupApp project folder 
//    — the one containing MainTabView.swift and WinTheDayView.swift.
// ✅ All files must also be added to the Xcode project navigator 
//    and included in the StudyGroupApp build target.
// ❌ Do not place files in subfolders like Outcast or Preview Content.
