c = open('android/app/build.gradle', encoding='utf-8').read()

old = '    implementation \n    implementation \n'
new = ''

if old in c:
    c = c.replace(old, new)
    open('android/app/build.gradle', 'w', encoding='utf-8').write(c)
    print("Fixed!")
else:
    print("Not found - trying regex")
    import re
    c2 = re.sub(r'    implementation \s*\n    implementation \s*\n', '', c)
    if c2 != c:
        open('android/app/build.gradle', 'w', encoding='utf-8').write(c2)
        print("Fixed with regex!")
    else:
        print("Still not found")
        idx = c.find('crashlytics-ktx')
        print(repr(c[idx:idx+100]))
