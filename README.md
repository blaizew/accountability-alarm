# Accountability Alarm

Personal iOS app that adds AI-powered conversational accountability to alarm dismissal.

## Setup

1. Open `AccountabilityAlarm/AccountabilityAlarm.xcodeproj` in Xcode
2. Create `AccountabilityAlarm/AccountabilityAlarm/APIKeys.swift`:
   ```swift
   enum APIKeys {
       static let anthropicAPIKey = "your-key-here"
   }
   ```
3. Select your development team in Signing & Capabilities
4. Build and run on your device

## Architecture

MVVM + Service Layer:
- **Views** (SwiftUI) → **ViewModels** (`@Observable`) → **Services** (singletons) → **Models** (SwiftData)
- Claude API (Haiku) for conversations (~$0.003/conversation)
- Apple Speech framework for voice input
- AVSpeechSynthesizer for TTS output
- UNUserNotificationCenter for alarm notifications

## Permissions Required

- Notifications (alarm scheduling)
- Microphone (voice memos + speech input)
- Speech Recognition (voice-to-text during conversations)

## How It Works

1. Create an alarm with a time, label, and **reason** (voice or text)
2. When the alarm fires, tap the notification to open a conversation
3. The AI plays back your own reasoning and does sleep math
4. 4 escalation rings: Nudge → Math → Mirror → Preview
5. You can comply, snooze, or override — all logged for pattern tracking
