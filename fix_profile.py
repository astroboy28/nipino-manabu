import re

# ── Check User model for isVerified ───────────────────────────────────────
c = open('lib/models/models.dart', encoding='utf-8').read()
idx = c.find('class User')
print("User model:")
print(c[idx:idx+400])
print("---")

# ── Fix profile_screen.dart delete account ────────────────────────────────
p = open('lib/screens/profile/profile_screen.dart', encoding='utf-8').read()
idx2 = p.find('delete')
if idx2 == -1:
    idx2 = p.find('Delete')
print("Delete section:")
print(p[idx2:idx2+300])
