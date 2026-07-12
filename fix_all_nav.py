import re

def fix_nav(path, current_index, self_route):
    c = open(path, encoding='utf-8').read()
    
    # Find the AppBottomNav onTap switch block
    idx = c.find('AppBottomNav(')
    if idx == -1:
        print(f"No AppBottomNav in {path}")
        return
    
    # Find the switch block
    switch_idx = c.find('switch (i) {', idx)
    if switch_idx == -1:
        print(f"No switch in {path}")
        return
    
    # Find end of switch block
    end_idx = c.find('\n                }', switch_idx) + len('\n                }')
    
    old_switch = c[switch_idx:end_idx]
    
    new_switch = f"""switch (i) {{
                  case 0: Navigator.pushReplacementNamed(context, '/home'); break;
                  case 1: Navigator.pushReplacementNamed(context, '/lessons'); break;
                  case 2: Navigator.pushReplacementNamed(context, '/quiz', arguments: {{'level': 'N5', 'category': 'kanji'}}); break;
                  case 3: Navigator.pushReplacementNamed(context, '/leaderboard'); break;
                  case 4: Navigator.pushReplacementNamed(context, '/duels'); break;
                  case 5: Navigator.pushReplacementNamed(context, '/profile'); break;
                }}"""
    
    if old_switch in c:
        c = c.replace(old_switch, new_switch)
        print(f"Switch fixed in {path.split('/')[-1]}")
    else:
        print(f"Switch NOT FOUND in {path.split('/')[-1]}")
        print(repr(old_switch[:100]))
        return

    # Fix currentIndex
    if 'currentIndex: _navIndex' not in c:
        old_ci = f'currentIndex: {current_index},'
        # Find what the current index actually is
        ci_idx = c.find('currentIndex:', idx)
        ci_end = c.find(',', ci_idx)
        actual_ci = c[ci_idx:ci_end+1]
        if actual_ci != f'currentIndex: {current_index},':
            c = c.replace(actual_ci, f'currentIndex: {current_index},', 1)
            print(f"currentIndex fixed to {current_index}")

    open(path, 'w', encoding='utf-8').write(c)
    print(f"Saved {path.split('/')[-1]}")

# Fix each screen
fix_nav('lib/screens/lessons/lesson_screen.dart', 1, '/lessons')
fix_nav('lib/screens/leaderboard/leaderboard_screen.dart', 3, '/leaderboard')
fix_nav('lib/screens/profile/profile_screen.dart', 5, '/profile')
fix_nav('lib/screens/quiz/result_screen.dart', 2, '/result')

# Fix home screen separately - it uses _navIndex and pushNamed not pushReplacementNamed
c = open('lib/screens/home/home_screen.dart', encoding='utf-8').read()
idx = c.find('AppBottomNav(')
switch_idx = c.find('switch (i) {', idx)
end_idx = c.find('\n                }', switch_idx) + len('\n                }')
old_switch = c[switch_idx:end_idx]

new_switch = """switch (i) {
                  case 1: Navigator.pushNamed(context, '/lessons'); break;
                  case 2: Navigator.pushNamed(context, '/quiz',
                      arguments: {'level': context.read<AuthProvider>().user?.currentLevel ?? 'N5','category':'kanji'}); break;
                  case 3: Navigator.pushNamed(context, '/leaderboard'); break;
                  case 4: Navigator.pushNamed(context, '/duels'); break;
                  case 5: Navigator.pushNamed(context, '/profile'); break;
                }"""

if old_switch in c:
    c = c.replace(old_switch, new_switch)
    open('lib/screens/home/home_screen.dart', 'w', encoding='utf-8').write(c)
    print("Home screen nav fixed!")
else:
    print("Home screen switch NOT FOUND")
    print(repr(old_switch[:150]))

print("\nAll nav fixes done!")
