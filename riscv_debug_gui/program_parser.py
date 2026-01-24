def _strip_comment(line: str) -> str:
    if "//" in line:
        line = line.split("//", 1)[0]
    if "#" in line:
        line = line.split("#", 1)[0]
    return line.strip()

def parse_program_file(path: str) -> list[tuple[int, int]]:
    items: list[tuple[int, int]] = []
    base = 0
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            s = _strip_comment(raw)
            if not s:
                continue

            if s.startswith("@"):
                addr_s = s[1:].strip()
                base = int(addr_s, 16) if not addr_s.lower().startswith("0x") else int(addr_s, 0)
                continue

            if ":" in s:
                a_s, d_s = s.split(":", 1)
                a_s, d_s = a_s.strip(), d_s.strip()
                addr = int(a_s, 0) if a_s.lower().startswith("0x") else int(a_s, 16)
                word = int(d_s, 0) if d_s.lower().startswith("0x") else int(d_s, 16)
                items.append((addr & 0xFFFFFFFF, word & 0xFFFFFFFF))
                continue

            word = int(s, 0) if s.lower().startswith("0x") else int(s, 16)
            items.append((base & 0xFFFFFFFF, word & 0xFFFFFFFF))
            base = (base + 4) & 0xFFFFFFFF

    return items
