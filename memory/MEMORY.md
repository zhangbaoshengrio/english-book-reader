# Project Memory

## Workflow
- **上传** = build APK (`flutter build apk --release`) + create GitHub Release (`gh release create`)
- **只有用户说"上传"时才执行**，不要主动上传

## Environment
- Flutter path: `/Users/zhangbaosheng/development/flutter/bin/flutter`
- GitHub repo: `zhangbaoshengrio/english-book-reader`
- Package: `com.zhangbaosheng.english_reader` (approx)
- Latest release: v1.9.7

## Key Files
- `lib/services/voice_engine_service.dart` — voice engine model + service
- `lib/screens/voice_engine_screen.dart` — voice engine settings UI
- `lib/services/ai_service.dart` — AI engine (ChatGPT/Gemini/DeepSeek)
- `lib/services/translation_service.dart` — translation engines + AI engine bridge
- `lib/widgets/floating_translate_card.dart` — sentence translation overlay card
- `lib/widgets/floating_word_card.dart` — word lookup overlay card
- `lib/screens/reader_screen.dart` — main reading screen
