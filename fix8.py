c=open('lib/screens/home/home_screen.dart',encoding='utf-8').read() 
c=c.replace("import '../../widgets/level_progress_card.dart';",'') 
c=c.replace("import '../../widgets/section_header.dart';",'') 
open('lib/screens/home/home_screen.dart','w',encoding='utf-8').write(c) 
