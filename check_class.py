with open(r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\Dart\vsn.dart', 'r') as f:
    content = f.read()
# Count occurrences of 'class MutableStore'
count = content.count('class MutableStore')
print('Found \
class
MutableStore\ ' + str(count) + ' times')
if count > 1:
    # Find all positions
    import re
    positions = []
    start = 0
    while True:
        pos = content.find('class MutableStore', start)
        if pos == -1:
            break
        positions.append(pos)
        start = pos + 1
    print('Positions: ' + str(positions))
