content = open('lib/theme/app_theme.dart', encoding='utf-8').read() 
content = content.replace('static const Color blue', 'static const Color amber = Color(0xFFE88C00);\n  static const Color blue') 
content = content.replace('cardTheme: CardTheme(', 'cardTheme: CardThemeData(') 
open('lib/theme/app_theme.dart', 'w', encoding='utf-8').write(content) 
