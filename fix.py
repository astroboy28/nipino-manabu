c=open('pubspec.yaml',encoding='utf-8').read() 
c=c.replace('version: 1.0.0+51','version: 1.0.0+55') 
open('pubspec.yaml','w',encoding='utf-8').write(c) 
