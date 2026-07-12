import os

screens = [
    ('home', 'lib/screens/home/home_screen.dart'),
    ('lessons', 'lib/screens/lessons/lesson_screen.dart'),
    ('leaderboard', 'lib/screens/leaderboard/leaderboard_screen.dart'),
    ('profile', 'lib/screens/profile/profile_screen.dart'),
    ('result', 'lib/screens/quiz/result_screen.dart'),
    ('store', 'lib/screens/store/store_screen.dart'),
]

for name, path in screens:
    if not os.path.exists(path):
        print(f"{name}: FILE NOT FOUND")
        continue
    c = open(path, encoding='utf-8').read()
    idx = c.find('AppBottomNav')
    if idx == -1:
        print(f"{name}: NO AppBottomNav")
        continue
    snippet = c[idx:idx+500]
    print(f"\n=== {name.upper()} (currentIndex check) ===")
    # Check currentIndex
    ci_idx = snippet.find('currentIndex:')
    print(snippet[ci_idx:ci_idx+20])
    # Check all cases
    for i in range(6):
        if f'case {i}:' in snippet:
            case_idx = snippet.find(f'case {i}:')
            print(snippet[case_idx:case_idx+70])
        else:
            print(f"  case {i}: MISSING")
