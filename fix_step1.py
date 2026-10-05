with open('generate_docs.py', 'r', encoding='utf-8') as f:
    lines = f.readlines()
new_lines = lines[50:]
with open('generate_docs.py', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
print(f'Removed first 50 lines, new total: {len(new_lines)}')