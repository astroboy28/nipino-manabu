content = open('lib/screens/admin/admin_screen.dart', encoding='utf-8').read() 
import sys 
lines = content.split('\n') 
top_imports = [] 
body_lines = [] 
for line in lines: 
    if line.strip().startswith('import ') and 'class ' not in '\n'.join(body_lines[-5:] if body_lines else []): 
        top_imports.append(line) if line not in top_imports else None 
    else: 
        body_lines.append(line) 
open('lib/screens/admin/admin_screen.dart', 'w', encoding='utf-8').write('\n'.join(body_lines)) 
