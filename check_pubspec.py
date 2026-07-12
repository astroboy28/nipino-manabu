c = open('pubspec.yaml', encoding='utf-8').read()
idx = c.find('assets/lottie/')
print(repr(c[idx-20:idx+60]))
