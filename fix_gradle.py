c = open('android/app/build.gradle', encoding='utf-8').read()

old = """    implementation "com.google.firebase:firebase-crashlytics-ktx"
    implementation
    implementation
    implementation "androidx.core:core-ktx:1.12.0"""

new = """    implementation "com.google.firebase:firebase-crashlytics-ktx"
    implementation "androidx.core:core-ktx:1.12.0"""

if old in c:
    c = c.replace(old, new)
    open('android/app/build.gradle', 'w', encoding='utf-8').write(c)
    print("Fixed!")
else:
    print("Not found")
    idx = c.find('firebase-crashlytics-ktx')
    print(repr(c[idx:idx+150]))
