content = open('lib/screens/quiz/result_screen.dart', encoding='utf-8').read() 
content = content.replace('const ResultScreen({super.key});', 'const ResultScreen({super.key, this.session});\n  final dynamic session;') 
open('lib/screens/quiz/result_screen.dart', 'w', encoding='utf-8').write(content) 
