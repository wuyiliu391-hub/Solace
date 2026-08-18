# Dart 类成员解析器（字符串插值/注释感知的括号计数）。
# 用法：python scripts/class_members.py <file.dart> <class_decl_line_1based>
# 输出：每个 depth-1 成员的 起始行-结束行(含) + 签名首行（注释/注解归属其后成员）。
import io, sys


def parse_members(lines, class_line):
    """返回 (members, body_open_idx, body_close_idx)；行号 0-based。
    members: [(start_idx, end_idx_inclusive)] 不含前置注释（由 attach_trivia 归属）。"""
    n = len(lines)
    i = class_line - 1
    while i < n and "{" not in lines[i]:
        i += 1
    body_open = i
    depth = 1
    state = "code"
    interp = []  # 元素: (进入插值时的depth, 字符串状态, raw_mode)
    raw_mode = False
    members = []
    cur_start = None
    line = i + 1
    while line < n:
        s = lines[line]
        j = 0
        while j < len(s):
            c = s[j]
            nxt = s[j + 1] if j + 1 < len(s) else ""
            if state == "code":
                if depth == 1 and cur_start is None and not c.isspace():
                    cur_start = line
                if c == "/" and nxt == "/":
                    break
                if c == "/" and nxt == "*":
                    state = "block"
                    j += 2
                    continue
                if c == "r" and nxt in ("'", '"'):
                    raw_mode = True
                    j += 1
                    continue
                if s[j:j + 3] == "'''":
                    state = "ts"
                    j += 3
                    continue
                if s[j:j + 3] == '"""':
                    state = "td"
                    j += 3
                    continue
                if c == "'":
                    state = "sq"
                    j += 1
                    continue
                if c == '"':
                    state = "dq"
                    j += 1
                    continue
                if c == "{":
                    depth += 1
                    j += 1
                    continue
                if c == "}":
                    if interp and depth == interp[-1][0]:
                        st = interp.pop()
                        state = st[1]
                        raw_mode = st[2]
                        j += 1
                        continue
                    depth -= 1
                    if depth == 0:
                        return members, body_open, line
                    if depth == 1 and cur_start is not None:
                        members.append((cur_start, line))
                        cur_start = None
                    j += 1
                    continue
                if c == ";" and depth == 1:
                    if cur_start is not None:
                        members.append((cur_start, line))
                        cur_start = None
                    j += 1
                    continue
                j += 1
                continue
            if state in ("sq", "dq", "ts", "td"):
                if c == "$" and nxt == "{":
                    interp.append((depth, state, raw_mode))
                    state = "code"
                    raw_mode = False
                    j += 2
                    continue
                if not raw_mode and c == "\\":
                    j += 2
                    continue
                if state == "sq" and c == "'":
                    state = "code"
                    raw_mode = False
                elif state == "dq" and c == '"':
                    state = "code"
                    raw_mode = False
                elif state == "ts" and s[j:j + 3] == "'''":
                    state = "code"
                    raw_mode = False
                    j += 3
                    continue
                elif state == "td" and s[j:j + 3] == '"""':
                    state = "code"
                    raw_mode = False
                    j += 3
                    continue
                j += 1
                continue
            if state == "block":
                if c == "*" and nxt == "/":
                    state = "code"
                    j += 2
                    continue
                j += 1
                continue
        line += 1
    return members, body_open, n - 1


def attach_trivia(members, body_open, lines):
    """把成员上方紧邻的注释/注解行归属到该成员。"""
    out = []
    prev_end = body_open
    for (a, b) in members:
        k = a - 1
        while k > prev_end:
            t = lines[k].strip()
            if t == "":
                break
            if t.startswith("//") or t.startswith("@"):
                k -= 1
                continue
            break
        start = k + 1 if k + 1 < a else a
        out.append((start, b))
        prev_end = b
    return out


if __name__ == "__main__":
    path, cls_line = sys.argv[1], int(sys.argv[2])
    with io.open(path, "r", encoding="utf-8") as f:
        lines = f.read().split("\n")
    members, body_open, body_close = parse_members(lines, cls_line)
    members = attach_trivia(members, body_open, lines)
    total = sum(b - a + 1 for a, b in members)
    print("# class body: %d..%d, members=%d, member-lines=%d"
          % (body_open + 1, body_close + 1, len(members), total))
    for (a, b) in members:
        sig = ""
        for k in range(a, b + 1):
            if lines[k].strip():
                sig = lines[k].strip()
                break
        print("%d-%d (%dL) | %s" % (a + 1, b, b - a + 1, sig[:110]))
