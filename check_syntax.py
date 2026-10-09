
with open(r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\Dart\vsn.dart', 'r') as f:
    lines = f.readlines()
# Check for basic syntax errors that would prevent parsing
brace_count = 0
paren_count = 0
bracket_count = 0
in_comment = False  # /* ... */
in_line_comment = False  # // ...
in_string = False
string_char = ''
escape_next = False
for i, line in enumerate(lines):
    original_line = line
    line = line.rstrip()
    j = 0
    while j < len(line):
        c = line[j]
        if escape_next:
            escape_next = False
        elif c == '\\\\':
            escape_next = True
        elif not in_comment and not in_line_comment and not in_string:
            if c == '/' and j + 1 < len(line):
                if line[j+1] == '/':
                    in_line_comment = True
                    j += 1  # Skip next char
                elif line[j+1] == '*':
                    in_comment = True
                    j += 1  # Skip next char
            elif c == '\
 or c == \"
\):
                in_string = True
                string_char = c
            elif c == '{':
                brace_count += 1
            elif c == '}':
                brace_count -= 1
                if brace_count < 0:
                    print('ERROR: Unmatched closing brace at line ' + str(i+1) + ', column ' + str(j+1))
                    print('  Line: ' + original_line.rstrip())
            elif c == '(':
                paren_count += 1
            elif c == ')':
                paren_count -= 1
                if paren_count < 0:
                    print('ERROR: Unmatched closing parenthesis at line ' + str(i+1) + ', column ' + str(j+1))
                    print('  Line: ' + original_line.rstrip())
            elif c == '[':
                bracket_count += 1
            elif c == ']':
                bracket_count -= 1
                if bracket_count < 0:
                    print('ERROR: Unmatched closing bracket at line ' + str(i+1) + ', column ' + str(j+1))
                    print('  Line: ' + original_line.rstrip())
        elif not in_comment and not in_line_comment and in_string:
            if c == string_char:
                in_string = False
        elif in_line_comment:
            if c == '\\n':
                in_line_comment = False
        elif in_comment:
            if c == '*' and j + 1 < len(line) and line[j+1] == '/':
                in_comment = False
                j += 1  # Skip next char
        j += 1
if brace_count != 0:
    print('ERROR: Unmatched braces at end: ' + str(brace_count))
if paren_count != 0:
    print('ERROR: Unmatched parentheses at end: ' + str(paren_count))
if bracket_count != 0:
    print('ERROR: Unmatched brackets at end: ' + str(bracket_count))
if in_comment:
    print('ERROR: Unterminated block comment at end')
if in_string:
    print('ERROR: Unterminated string at end')
print('Syntax check completed')

