with open('docs.html', 'r', encoding='utf-8') as f:
    content = f.read()

marker = '</section>\n      <div class="container doc">\n        <p class="eyebrow">28 &middot; Streaming'
idx = content.find(marker)

if idx != -1:
    new_content = content[:idx] + '</section>\n'
    with open('docs_part1.html', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('Part 1 written, length:', len(new_content))
else:
    print('Marker not found')