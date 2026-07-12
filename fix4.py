c=open('lib/models/models.dart',encoding='utf-8').read() 
c=c.replace('required this.level,\n    required this.completedTopics','required this.level,\n    this.percent=0.0,\n    required this.completedTopics') 
c=c.replace('final String level;','final String level;\n  final double percent;') if 'final double percent' not in c else c 
open('lib/models/models.dart','w',encoding='utf-8').write(c) 
