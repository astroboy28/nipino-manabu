c = open('lib/models/social_models.dart', encoding='utf-8').read()
idx = c.find('class OpenDuelRoom')
print(c[idx:idx+600])
