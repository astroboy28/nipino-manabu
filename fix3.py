c=open('lib/theme/app_theme.dart',encoding='utf-8').read() 
parts=c.split('static const Color amber = Color(0xFFE88C00);') 
result=parts[0]+'static const Color amber = Color(0xFFE88C00);'+''.join(parts[2:]) if len(parts) else c 
open('lib/theme/app_theme.dart','w',encoding='utf-8').write(result) 
