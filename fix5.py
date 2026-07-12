c=open('lib/theme/app_theme.dart',encoding='utf-8').read() 
lines=c.split('\n') 
lines=[l for l in lines if not (l.strip()=='static const Color amber = Color(0xFFE88C00);' and lines.index(l)
open('lib/theme/app_theme.dart','w',encoding='utf-8').write('\n'.join(lines)) 
