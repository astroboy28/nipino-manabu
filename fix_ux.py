import re

# Fix profile screen - add settings link and quiz preferences link
c = open('lib/screens/profile/profile_screen.dart', encoding='utf-8').read()

# Add settings and quiz preferences to the LEGAL section
old = """                  _LinkRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy',
                    onTap: () {}),
                  _LinkRow(icon: Icons.description_outlined, label: 'Terms of Service',
                    onTap: () {}),"""
new = """                  _LinkRow(icon: Icons.settings_outlined, label: 'Settings',
                    onTap: () => Navigator.pushNamed(context, '/settings')),
                  _LinkRow(icon: Icons.timer_outlined, label: 'Quiz Preferences',
                    onTap: () => Navigator.pushNamed(context, '/quiz-preferences')),
                  _LinkRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy',
                    onTap: () {}),
                  _LinkRow(icon: Icons.description_outlined, label: 'Terms of Service',
                    onTap: () {}),"""
if old in c:
    c = c.replace(old, new)
    print("1. Settings and Quiz Preferences links added to profile!")
else:
    print("1. NOT FOUND")
    idx = c.find('Privacy Policy')
    print(repr(c[idx-100:idx+50]))

open('lib/screens/profile/profile_screen.dart', 'w', encoding='utf-8').write(c)

# Add haptic feedback to quiz answer selection
q = open('lib/screens/quiz/quiz_screen.dart', encoding='utf-8').read()

old2 = "import 'dart:async';"
new2 = "import 'dart:async';\nimport 'package:flutter/services.dart';"
if old2 in q:
    q = q.replace(old2, new2)
    print("2. Services import added!")
else:
    print("2. NOT FOUND")

old3 = "    if (isCorrect) {\n      _session!.correctCount++;\n      _sound.playCorrect();"
new3 = "    HapticFeedback.lightImpact();\n    if (isCorrect) {\n      _session!.correctCount++;\n      _sound.playCorrect();"
if old3 in q:
    q = q.replace(old3, new3)
    print("3. Haptic feedback added!")
else:
    print("3. NOT FOUND")

open('lib/screens/quiz/quiz_screen.dart', 'w', encoding='utf-8').write(q)
print("\nAll fixes saved!")
