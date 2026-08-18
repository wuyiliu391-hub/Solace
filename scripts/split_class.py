# 通用巨型类拆分器 v3：Core 基类 + 链式 mixin + part 模式。
# build: CHAIN-4
# - mixin 链：parts[i] on parts[i-1]（首段 on Core）→ 跨段调用天然可见
# - 成员名仅从签名首个代码行提取，避免把值表达式里的 RegExp( 等当名字
# - static 成员强制留主类；搬移体内 statics 裸引用改写为 Class.xxx
import io, json, os, re, sys, time, hashlib

def read(path):
    with io.open(path, "r", encoding="utf-8") as f:
        return f.read()

def wait_fresh(path, marker, timeout=40):
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            if marker in read(path):
                return True
        except OSError:
            pass
        time.sleep(1)
    return False

def parse_members(lines, class_line):
    n = len(lines)
    i = class_line - 1
    while i < n and "{" not in lines[i]:
        i += 1
    body_open = i
    depth = 1
    state = "code"
    interp = []
    raw_mode = False
    members = []
    cur_start = None
    paren = 0
    line = i + 1
    while line < n:
        s = lines[line]
        j = 0
        while j < len(s):
            c = s[j]
            nxt = s[j + 1] if j + 1 < len(s) else ""
            if state == "code":
                if c == "/" and nxt == "/":
                    break
                if c == "/" and nxt == "*":
                    state = "block"; j += 2; continue
                # 成员起点检测必须晚于注释判断：否则 `; // ...` 的斜杠
                # 会被误当新成员起点，产生吞并后续成员的幽灵成员；
                # `;` 与 `}` 自身也永远不能作为成员起点（表达式体 `};` 尾）
                if (depth == 1 and cur_start is None
                        and not c.isspace() and c not in (";", "}")):
                    cur_start = line
                if c == "r" and nxt in ("'", '"'):
                    raw_mode = True; j += 1; continue
                if s[j:j+3] == "'''":
                    state = "ts"; j += 3; continue
                if s[j:j+3] == '"""':
                    state = "td"; j += 3; continue
                if c == "'":
                    state = "sq"; j += 1; continue
                if c == '"':
                    state = "dq"; j += 1; continue
                if c == "(":
                    paren += 1; j += 1; continue
                if c == ")":
                    if paren > 0:
                        paren -= 1
                    j += 1; continue
                if c == "{":
                    depth += 1; j += 1; continue
                if c == "}":
                    if interp and depth == interp[-1][0]:
                        st = interp.pop()
                        state = st[1]; raw_mode = st[2]
                        j += 1; continue
                    depth -= 1
                    if depth == 0:
                        return members, body_open, line
                    if depth == 1 and cur_start is not None and paren == 0:
                        members.append((cur_start, line))
                        cur_start = None
                        paren = 0
                    j += 1; continue
                if c == ";" and depth == 1 and paren == 0:
                    if cur_start is not None:
                        members.append((cur_start, line))
                        cur_start = None
                        paren = 0
                    j += 1; continue
                j += 1; continue
            if state in ("sq", "dq", "ts", "td"):
                if c == "$" and nxt == "{":
                    interp.append((depth, state, raw_mode))
                    state = "code"; raw_mode = False
                    j += 2; continue
                if not raw_mode and c == "\\":
                    j += 2; continue
                if state == "sq" and c == "'":
                    state = "code"; raw_mode = False
                elif state == "dq" and c == '"':
                    state = "code"; raw_mode = False
                elif state == "ts" and s[j:j+3] == "'''":
                    state = "code"; raw_mode = False; j += 3; continue
                elif state == "td" and s[j:j+3] == '"""':
                    state = "code"; raw_mode = False; j += 3; continue
                j += 1; continue
            if state == "block":
                if c == "*" and nxt == "/":
                    state = "code"; j += 2; continue
                j += 1; continue
        line += 1
    return members, body_open, n - 1

def attach_trivia(members, body_open, lines):
    out = []
    prev_end = body_open
    for (a, b) in members:
        k = a - 1
        while k > prev_end:
            t = lines[k].strip()
            if t == "":
                break
            if t.startswith("//") or t.startswith("@"):
                k -= 1; continue
            break
        start = k + 1 if k + 1 < a else a
        out.append((start, b))
        prev_end = b
    return out

def first_code_line(chunk):
    for l in chunk:
        t = l.strip()
        if t and not t.startswith("//") and not t.startswith("@"):
            return t
    return ""

def member_name(chunk, cls_name):
    """成员名只从签名首个代码行提取（足够可靠，不看方法体）。"""
    t = first_code_line(chunk)
    if not t:
        return "?"
    if t.startswith("static "):
        t = t[len("static "):]
    if re.match(re.escape(cls_name) + r"\s*(\(|\.)", t):
        return cls_name
    # getter/setter
    m = re.search(r"\b(?:get|set)\s+([_A-Za-z]\w*)", t)
    if m:
        return m.group(1)
    # 字段：名字后跟 = 或 ; 且出现在首个 '(' 之前
    paren_pos = t.find("(")
    eq = re.search(r"([_A-Za-z]\w*)\s*=(?!=)", t)
    if eq and (paren_pos < 0 or eq.start() < paren_pos):
        return eq.group(1)
    semi = re.search(r"([_A-Za-z]\w*)\s*;", t)
    if semi and (paren_pos < 0 or semi.start() < paren_pos):
        return semi.group(1)
    # 方法：首个 id( 且 id 前不是类型关键字场景（取最后一个靠近 '(' 的候选）
    cands = list(re.finditer(r"([_A-Za-z]\w*)\s*\(", t))
    if cands:
        return cands[0].group(1)
    m = re.match(r"[_A-Za-z]\w*", t)
    if m:
        return m.group(0)
    return "?"

def sha(s):
    return hashlib.sha1(s.encode("utf-8")).hexdigest()[:10]

def main(cfg_path):
    print("BUILD: CHAIN-4")
    if cfg_path.endswith(".py"):
        ns = {}
        exec(read(cfg_path), ns)
        cfg = ns["CFG"]
    else:
        cfg = json.loads(read(cfg_path))
    src_path = cfg["file"]
    if not wait_fresh(src_path, cfg["freshness_marker"]):
        print("FATAL: freshness marker 不存在:", src_path); sys.exit(2)
    src = read(src_path)
    if cfg["freshness_marker"] not in src:
        print("FATAL: 二次校验失败"); sys.exit(2)

    lines = src.split("\n")
    class_line = cfg["class_line"]
    cls_name = cfg["class_name"]
    core_name = cfg["core_name"]
    assert lines[class_line - 1].strip().startswith("class " + cls_name)

    members, body_open, body_close = parse_members(lines, class_line)
    members = attach_trivia(members, body_open, lines)
    print("members:", len(members), "body:", body_open + 1, "..", body_close + 1)

    core_fields = set(cfg.get("core_fields", []))
    ctor_old = cfg["ctor_old"].strip()
    ctor_new = cfg["ctor_new"].rstrip()

    remaining = []
    static_names = set()
    kept_static_chunks = []
    ctor_found = False
    for (a, b) in members:
        chunk = lines[a:b + 1]
        text = "\n".join(chunk).strip()
        nm = member_name(chunk, cls_name)
        fc = first_code_line(chunk)
        if nm in core_fields and not fc.startswith("static "):
            continue
        if nm == cls_name and (fc.startswith(cls_name + "(") or fc.startswith(cls_name + ".")):
            if text == ctor_old:
                ctor_found = True
                continue
            print("FATAL: 构造函数原文不匹配:\n---\n%s\n---" % text); sys.exit(3)
        if fc.startswith("static "):
            static_names.add(nm)
            kept_static_chunks.append(chunk)
            continue
        remaining.append(chunk)

    if not ctor_found:
        print("FATAL: 未找到构造函数"); sys.exit(3)

    cuts = sorted(cfg["cut_lines"])
    idx_cuts = []
    for t in cuts:
        best, bd = None, 10**9
        for k, (a, b) in enumerate(members):
            d = abs((a + 1) - t)
            if d < bd:
                bd, best = d, k
        idx_cuts.append(best)
    idx_cuts = sorted(set(idx_cuts))
    segs = []
    prev = 0
    for c in idx_cuts:
        segs.append((prev, c)); prev = c
    segs.append((prev, len(members)))
    assert len(cfg["parts"]) == len(segs), "parts 数 %d != 分段数 %d" % (len(cfg["parts"]), len(segs))

    moved_groups = []
    kept_members = []
    for si, (s, e) in enumerate(segs):
        pdef = cfg["parts"][si]
        seg_names = set(member_name(lines[a:b+1], cls_name) for (a, b) in members[s:e])
        chunks = [ch for ch in remaining if member_name(ch, cls_name) in seg_names]
        if pdef.get("main"):
            kept_members.extend(chunks)
        else:
            moved_groups.append((pdef, chunks))

    covered = set(id(ch) for _, chs in moved_groups for ch in chs) | set(id(ch) for ch in kept_members)
    for ch in remaining:
        if id(ch) not in covered:
            kept_members.append(ch)

    part_directives = []
    written = []
    prev_on = core_name
    for pdef, chunks in moved_groups:
        body = "\n\n".join("\n".join(ch).rstrip() for ch in chunks)
        for nm in static_names:
            body = re.sub(r"(?<![\w.])" + re.escape(nm) + r"\b", cls_name + "." + nm, body)
        content = (
            pdef["doc"] + "\n"
            "// 本文件是 " + src_path.split("/")[-1] + " 的 part，与其共同构成一个库。\n\n"
            "part of '" + cfg["part_of"] + "';\n\n"
            "mixin " + pdef["mixin"] + " on " + prev_on + " {\n"
            + body + "\n}\n"
        )
        prev_on = pdef["mixin"]
        out_path = pdef["file"]
        d = out_path.rsplit("/", 1)[0] if "/" in out_path else "."
        if not os.path.isdir(d):
            os.makedirs(d, exist_ok=True)
        with io.open(out_path, "w", encoding="utf-8", newline="") as f:
            f.write(content)
        written.append((out_path, sha(content)))
        part_directives.append("part '%s';" % pdef.get("directive", out_path.split("/")[-1]))

    head = lines[:body_open + 1]
    tail = lines[body_close:]
    head_text = "\n".join(head)
    head_text = re.sub(
        r"class %s \{" % cls_name,
        "class %s extends %s with %s {" % (cls_name, core_name, ", ".join(pd["mixin"] for pd, _ in moved_groups)),
        head_text,
    )
    m = list(re.finditer(r"^import .*;$", head_text, re.M))
    ins = "\n\n" + "\n".join(part_directives)
    if m:
        last = m[-1]
        head_text = head_text[:last.end()] + ins + head_text[last.end():]
    else:
        head_text += ins
    core_text = cfg["core_text"].rstrip() + "\n\n"
    head_text = head_text[:head_text.rindex("class " + cls_name)] + core_text + head_text[head_text.rindex("class " + cls_name):]

    inner = [ctor_new]
    if kept_members:
        inner.append("\n".join("\n".join(ch).rstrip() for ch in kept_members))
    if kept_static_chunks:
        inner.append("\n".join("\n".join(ch).rstrip() for ch in kept_static_chunks))
    new_src = head_text + "\n" + "\n\n".join(inner) + "\n" + "\n".join(tail) + "\n"
    new_src = re.sub(r"\n{4,}", "\n\n\n", new_src)
    with io.open(src_path, "w", encoding="utf-8", newline="") as f:
        f.write(new_src)
    written.append((src_path, sha(new_src)))
    print("WROTE:")
    for p, h in written:
        print(" ", p, h)

if __name__ == "__main__":
    main(sys.argv[1])
