c = open('pubspec.yaml', encoding='utf-8').read()
old = "    - assets/animations/\n    - assets/lottie/\n  fonts:"
new = "    - assets/animations/\n    - assets/lottie/\n    - assets/sounds/\n  fonts:"
if old in c:
    c = c.replace(old, new)
    open('pubspec.yaml', 'w', encoding='utf-8').write(c)
    print("Fixed!")
else:
    print("Not found")
