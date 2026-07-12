c=open('lib/screens/profile/profile_screen.dart',encoding='utf-8').read() 
c=c.replace("import '../../models/models.dart';","import '../../models/models.dart' hide Badge;") 
open('lib/screens/profile/profile_screen.dart','w',encoding='utf-8').write(c) 
