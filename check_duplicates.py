
with open(r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\Dart\vsn.dart', 'r') as f:
    content = f.read()
# Count occurrences of 'void writeFile'
count = content.count('void writeFile')
print('Found \
void
writeFile\ ' + str(count) + ' times')
if count > 1:
    import re
    positions = []
    start = 0
    while True:
        pos = content.find('void writeFile', start)
        if pos == -1:
            break
        positions.append(pos)
        start = pos + 1
    print('Positions: ' + str(positions))

