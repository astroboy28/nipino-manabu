c=open('android/app/build.gradle',encoding='utf-8').read() 
c=c.replace('coreLibraryDesugaring "com.android.tools.desugar_jdk_libs_nio:2.1.4"','coreLibraryDesugaring "com.android.tools.desugar_jdk_libs:1.2.3"') 
open('android/app/build.gradle','w',encoding='utf-8').write(c) 
