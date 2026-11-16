#!/usr/bin/env python3
"""Reject CJK ideographs in source comments without rejecting localized UI strings."""
import ast
import io
from pathlib import Path
import re
import tokenize

ROOT = Path(__file__).resolve().parent.parent
CJK = re.compile(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\U00020000-\U000323af]')


def swift_comments(source):
    comments = []
    length = len(source)

    def code(index, interpolation=False):
        depth = 0
        while index < length:
            if source.startswith('//', index):
                end = source.find('\n', index)
                end = length if end < 0 else end
                comments.append((index, source[index:end]))
                index = end
            elif source.startswith('/*', index):
                start, nesting = index, 1
                index += 2
                while index < length and nesting:
                    if source.startswith('/*', index):
                        nesting += 1
                        index += 2
                    elif source.startswith('*/', index):
                        nesting -= 1
                        index += 2
                    else:
                        index += 1
                comments.append((start, source[start:index]))
            elif source[index] == '"':
                delimiter = '"""' if source.startswith('"""', index) else '"'
                index += len(delimiter)
                while index < length:
                    if source.startswith('\\(', index):
                        index = code(index + 2, True)
                    elif source[index] == '\\':
                        index += 2
                    elif source.startswith(delimiter, index):
                        index += len(delimiter)
                        break
                    else:
                        index += 1
            elif interpolation and source[index] == '(':
                depth += 1
                index += 1
            elif interpolation and source[index] == ')':
                index += 1
                if depth == 0:
                    return index
                depth -= 1
            else:
                index += 1
        return index

    code(0)
    return [(source.count('\n', 0, offset) + 1, value) for offset, value in comments]


def comments(path, source):
    if path.suffix == '.swift':
        return swift_comments(source)
    if path.suffix == '.py':
        result = [(t.start[0], t.string) for t in tokenize.generate_tokens(io.StringIO(source).readline) if t.type == tokenize.COMMENT]
        for node in ast.walk(ast.parse(source)):
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
                doc = ast.get_docstring(node, clean=False)
                if doc is not None:
                    result.append((node.body[0].lineno, doc))
        return result
    if path.suffix in {'.md', '.plist'}:
        return [(source.count('\n', 0, m.start()) + 1, m.group()) for m in re.finditer(r'<!--[\s\S]*?-->', source)]
    result = []
    quote = None
    for number, line in enumerate(source.splitlines(), 1):
        escaped = False
        for index, char in enumerate(line):
            if escaped:
                escaped = False
            elif char == '\\' and quote != "'":
                escaped = True
            elif quote:
                if char == quote:
                    quote = None
            elif char in {'"', "'"}:
                quote = char
            elif char == '#' and (index == 0 or line[index - 1].isspace()):
                result.append((number, line[index:]))
                break
    return result


def main():
    files = [ROOT / 'Package.swift']
    for folder in ['Sources', 'Tests', 'scripts', '.github', 'Resources']:
        files += [p for p in (ROOT / folder).rglob('*') if p.suffix in {'.swift', '.py', '.sh', '.yml', '.yaml', '.md', '.plist'}]
    failures = []
    for path in sorted(set(files)):
        for number, comment in comments(path, path.read_text()):
            if CJK.search(comment):
                failures.append(f'{path.relative_to(ROOT)}:{number}: comment contains CJK ideographs')
    if failures:
        print('\n'.join(failures))
        return 1
    print(f'Comment audit passed: {len(set(files))} source/config files; no CJK ideographs in comments or Python docstrings.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
