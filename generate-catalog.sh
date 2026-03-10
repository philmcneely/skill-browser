#!/bin/bash
# Generate skills.json catalog from all installed skills
# Run: bash generate-catalog.sh
# Output: docs/skills.json

set -euo pipefail

CUSTOM_SKILLS="$HOME/git/claude-agent/skills"
MARKETPLACE="$HOME/.claude/plugins/cache/claude-skills-marketplace"
TEMPLATES="$HOME/git/claude-agent/tools/skill-templates"
OUT_DIR="$(dirname "$0")/docs"
mkdir -p "$OUT_DIR"

python3 - "$CUSTOM_SKILLS" "$MARKETPLACE" "$TEMPLATES" "$OUT_DIR/skills.json" <<'PYEOF'
import sys, os, json, re

custom_dir, mp_dir, templates_dir, out_file = sys.argv[1:5]

skills = []
seen = set()

# Sanitize internal infra names for public site
SANITIZE = {
    "on HAL9000": "via GPU server",
    "HAL9000": "GPU server",
    "Kokoro": "local TTS",
    "VibeVoice": "cloned voice TTS",
    "Mac Studio": "inference server",
}

def sanitize(text):
    for old, new in SANITIZE.items():
        text = text.replace(old, new)
    return text

def parse_frontmatter(content):
    meta = {}
    if content.startswith("---"):
        end = content.find("---", 3)
        if end > 0:
            fm = content[3:end]
            for line in fm.splitlines():
                line = line.strip()
                if ":" in line and not line.startswith("-"):
                    k, v = line.split(":", 1)
                    v = v.strip().strip('"').strip("'")
                    meta[k.strip()] = v
                elif line.startswith("- ") and "triggers" in meta:
                    if isinstance(meta["triggers"], str):
                        meta["triggers"] = []
                    meta["triggers"].append(line[2:].strip())
                elif line.startswith("- "):
                    meta.setdefault("triggers", []).append(line[2:].strip())
            content = content[end+3:].strip()
    return meta, content

def add_skill(skill_dir, source):
    skill_md = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(skill_md):
        return
    name = os.path.basename(skill_dir)
    if name in seen or re.match(r'^\d', name):
        return
    seen.add(name)

    with open(skill_md) as f:
        content = f.read()

    meta, body = parse_frontmatter(content)

    description = meta.get("description", "")
    if not description:
        for line in body.splitlines():
            if line.startswith("# "):
                description = line[2:].strip()
                break

    triggers = meta.get("triggers", [])
    if isinstance(triggers, str):
        triggers = [triggers]
    skill_name = meta.get("name", name)

    # Template
    template = ""
    tf = os.path.join(templates_dir, name + ".md")
    if os.path.isfile(tf):
        with open(tf) as f:
            lines = f.readlines()
            template = "".join(lines[2:]).strip()

    # Docs — collect ALL available docs separately
    how_to_use = ""
    readme = ""
    htu_path = os.path.join(skill_dir, "HOW_TO_USE.md")
    readme_path = os.path.join(skill_dir, "README.md")
    if os.path.isfile(htu_path):
        with open(htu_path) as f:
            how_to_use = f.read()[:4000]
    if os.path.isfile(readme_path):
        with open(readme_path) as f:
            readme = f.read()[:4000]

    entry = {
        "name": skill_name,
        "dir_name": name,
        "description": sanitize(description[:300]),
        "triggers": triggers,
        "template": sanitize(template),
        "source": source,
    }

    # Only include non-empty doc fields
    if how_to_use:
        entry["how_to_use"] = sanitize(how_to_use)
    if readme:
        entry["readme"] = sanitize(readme)

    skills.append(entry)

# Custom skills
if os.path.isdir(custom_dir):
    for entry in sorted(os.listdir(custom_dir)):
        add_skill(os.path.join(custom_dir, entry), "fleet")

# Marketplace skills
if os.path.isdir(mp_dir):
    for root, dirs, files in os.walk(mp_dir):
        if "SKILL.md" in files and "references" not in root:
            add_skill(root, "marketplace")

skills.sort(key=lambda s: s["name"])

with open(out_file, "w") as f:
    json.dump({"skills": skills, "count": len(skills)}, f, indent=2)

print(f"Generated {len(skills)} skills -> {out_file}")
PYEOF
