with open('docs.html', 'r', encoding='utf-8') as f:
    content = f.read()

marker = '</section>\n      <div class="container doc">\n        <p class="eyebrow">28 &middot; Streaming'
idx = content.find(marker)
print('Found at:', idx)
if idx != -1:
    print(content[idx:idx+200])