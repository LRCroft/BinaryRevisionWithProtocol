part1 = open('docs_part1.html', 'r', encoding='utf-8').read()
part2 = open('part2.html', 'r', encoding='utf-8').read()
with open('docs.html', 'w', encoding='utf-8') as f:
    f.write(part1 + part2)