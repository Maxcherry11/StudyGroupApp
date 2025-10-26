// Codex Project Rules & Constraints
// ----------------------------------
// ✅ Target iOS 17.0 — You may use iOS 17 APIs (e.g., .bouncy, NavigationStack, modern toolbar placements).
// ✅ Prefer NavigationStack (NavigationView only if you need legacy behavior).
// ✅ Support iPhone screens first (mobile-first design).
// ✅ You may use modern SwiftUI components introduced through iOS 17 as needed.
// ✅ Keep layout simple, clean, and follow Apple’s Human Interface Guidelines.
// ✅ CloudKit must work offline and sync cleanly when iCloud is available.
// ✅ Do not hardcode logic based on goal names — use IDs or model structure.
// ✅ Emoji must sync using CloudKit.
// ✅ Visual polish is complete — do not alter animations or card layout unless requested.
// ✅ Confetti appears only when full goals are met, not partial.
// ✅ Splash screen must allow user selection (DJ, Ron, Deanna, Dimitri) and lock fields for others.
// ✅ Life Scoreboard and Win the Day must support dynamic updates from UI.
//
// Migration Notes (iOS 17)
// ----------------------------------
// • Update ALL targets (app, extensions, tests) → General & Build Settings → iOS Deployment Target = 17.0
// • If using CocoaPods: set `platform :ios, '17.0'` in Podfile and run `pod install`.
// • For your own Swift packages: set `platforms: [.iOS(.v17)]` in Package.swift.
// • Clean build folder (Shift+Cmd+K) and delete Derived Data if necessary.
// • Remove obsolete availability checks that only existed for iOS 15/16 support.
//
// Codex File Placement Rules
// --------------------------
// ✅ All new files must be saved in the main StudyGroupApp project folder 
//    — the one containing MainTabView.swift and WinTheDayView.swift.
// ✅ All files must also be added to the Xcode project navigator 
//    and included in the StudyGroupApp build target.
// ❌ Do not place files in subfolders like Outcast or Preview Content.

