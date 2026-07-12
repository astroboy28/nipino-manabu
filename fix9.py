c=open('lib/screens/admin/admin_screen.dart',encoding='utf-8').read() 
c=c.replace('SocialApiService.listChallenges','ApiService.listChallenges') 
open('lib/screens/admin/admin_screen.dart','w',encoding='utf-8').write(c) 
