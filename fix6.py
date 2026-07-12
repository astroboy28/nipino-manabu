c=open('lib/models/models.dart',encoding='utf-8').read() 
c=c.replace('final String level;\n  final double percent;','final String level;') 
c=c.replace('this.percent=0.0,\n    required this.completedTopics','required this.completedTopics') 
open('lib/models/models.dart','w',encoding='utf-8').write(c) 
