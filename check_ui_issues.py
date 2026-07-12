c = open('lib/screens/quiz/result_screen.dart', encoding='utf-8').read()
# Find icon section
idx = c.find('Icons.star_rounded')
print("RESULT ICON SECTION:")
print(c[idx-100:idx+300])
print("---")
# Find coins section
idx2 = c.find('coinsEarned')
print("COINS SECTION:")
print(c[idx2-50:idx2+200])
print("---")
# Check duel card
d = open('lib/screens/duel/duel_screen.dart', encoding='utf-8').read()
idx3 = d.find('_OpenRoomCard')
idx4 = d.find('class _OpenRoomCard')
print("DUEL CARD BUILD:")
print(d[idx4:idx4+800])
