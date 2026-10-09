
with open(r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\Dart\vsn.dart', 'r') as f:
    content = f.read()
# Count occurrences of 'writeFile' (case sensitive)
count_lower = content.count('writeFile')
count_upper = content.count('WriteFile')
print('\
writeFile\ occurrences: ' + str(count_lower))
print('\WriteFile\ occurrences: ' + str(count_upper))
# Find all positions of 'writeFile'
import re
matches = list(re.finditer(r'writeFile', content))
if matches:
    print('Positions of \writeFile\:')
    for i, match in enumerate(matches):
        pos = match.start()
        # Show context
        start = max(0, pos - 20)
        end = min(len(content), pos + 20)
        context = content[start:end]
        print('  Position ' + str(pos) + ': ' + repr(context))
else:
    print('No occurrences of \writeFile\ found')

