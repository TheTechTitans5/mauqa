"""
Lightweight static sanity checks for Dart sources when the Dart SDK is not available.
NOT a replacement for `flutter analyze` — it only catches structural mistakes:
  * unbalanced (), [], {} outside strings/comments
  * unterminated string literals
  * relative/package imports that point at files that do not exist
  * route builders in app_router.dart that reference undefined screen classes
Usage: python3 tools/dart_sanity.py app
"""
import os
import re
import sys

PAIRS = {')': '(', ']': '[', '}': '{'}


def check_balance(src: str):
    stack = []
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if src.startswith('/*', i):
            j = src.find('*/', i + 2)
            if j < 0:
                return f'unterminated block comment at line {line}'
            line += src.count('\n', i, j)
            i = j + 2
            continue
        m = re.match(r"r?('''|\"\"\"|'|\")", src[i:])
        if m:
            raw = m.group(0).startswith('r')
            q = m.group(1)
            j = i + len(m.group(0))
            depth = 0  # ${ } interpolation depth (approximate: tracks braces inside)
            while j < n:
                if not raw and src[j] == '\\':
                    j += 2
                    continue
                if not raw and src.startswith('${', j):
                    depth += 1
                    j += 2
                    continue
                if depth and src[j] == '}':
                    depth -= 1
                    j += 1
                    continue
                if depth == 0 and src.startswith(q, j):
                    break
                if len(q) == 1 and src[j] == '\n' and depth == 0:
                    return f'unterminated string starting line {line}'
                j += 1
            if j >= n:
                return f'unterminated string starting line {line}'
            line += src.count('\n', i, j)
            i = j + len(q)
            continue
        if c in '([{':
            stack.append((c, line))
        elif c in ')]}':
            if not stack or stack[-1][0] != PAIRS[c]:
                return f'unbalanced {c!r} at line {line} (open: {stack[-1] if stack else None})'
            stack.pop()
        i += 1
    if stack:
        return f'unclosed {stack[-1][0]!r} from line {stack[-1][1]}'
    return None


def main(root: str) -> int:
    lib = os.path.join(root, 'lib')
    pkg = 'mauqa'
    problems = 0
    files = []
    for base in (lib, os.path.join(root, 'test')):
        for d, _, fs in os.walk(base):
            files += [os.path.join(d, f) for f in fs if f.endswith('.dart')]
    for path in sorted(files):
        src = open(path, encoding='utf-8').read()
        err = check_balance(src)
        if err:
            print(f'{path}: {err}')
            problems += 1
        for imp in re.findall(r"^import '([^']+)'", src, re.M):
            if imp.startswith('package:'):
                if imp.startswith(f'package:{pkg}/'):
                    target = os.path.join(lib, imp[len(f'package:{pkg}/'):])
                else:
                    continue
            elif imp.startswith('dart:'):
                continue
            else:
                target = os.path.normpath(os.path.join(os.path.dirname(path), imp))
            if not os.path.exists(target):
                print(f'{path}: import not found -> {imp}')
                problems += 1
    # every class referenced as `const XScreen(` / `XScreen(` in the router must be declared somewhere
    router = open(os.path.join(lib, 'core/router/app_router.dart'), encoding='utf-8').read()
    declared = set()
    for path in files:
        declared |= set(re.findall(r'^class (\w+)', open(path, encoding='utf-8').read(), re.M))
    for name in sorted(set(re.findall(r'\b([A-Z]\w*(?:Screen|Shell))\(', router))):
        if name not in declared:
            print(f'router references undefined class {name}')
            problems += 1
    print(f'checked {len(files)} Dart files: {"OK" if problems == 0 else f"{problems} problem(s)"}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'app'))
