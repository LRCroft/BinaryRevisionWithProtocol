with open(r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\Dart\vsn.dart', 'r') as f:
    content = f.read()
count = content.count('void writeFile')
print('Found void writeFile ' + str(count) + ' times')
if count > 1:
    positions = []
    start = 0
    while True:
        pos = content.find('void writeFile', start)
        if pos == -1:
            break
        positions.append(pos)
        start = pos + 1
    print('Positions: ' + str(positions))
