repo = r"C:\Users\Administrator\Desktop\solace\lib\repositories\local_storage_repository.dart"
with open(repo, "r", encoding="utf-8-sig") as f:
    lines = f.readlines()

fixed = False
for i, line in enumerate(lines):
    if "currentAnchor TEXT )" in line and "currentAnchor TEXT, referenceImg" not in line and i > 1200:
        old_text = "currentAnchor TEXT )"
        new_text = 'currentAnchor TEXT, referenceImg TEXT, fixedSeed INTEGER NOT NULL DEFAULT -1, characterTag TEXT, styleLock TEXT NOT NULL DEFAULT "anime" )'
        lines[i] = line.replace(old_text, new_text)
        fixed = True
        print(f"Fixed line {i}")
        break

if fixed:
    with open(repo, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("Written!")
else:
    print("Pattern not found")