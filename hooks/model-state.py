#!/usr/bin/env python3
"""Load managed model files through Dosi before host file tools use them.

This is ordinary model validation, not a YAML converter. Cache only stable
versions actually loaded. The host may still read invalid files to repair them.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SUFFIXES = {".yaml", ".yml", ".json"}
PROTECTED = {"profiles.yml", "dosi-connections.yaml", "secrets.env", ".env"}
WRITES = {"Write", "Edit", "MultiEdit", "apply_patch", "Bash"}


def targets(payload, project):
    model_dir = project / "dosi"
    paths = {p.resolve() for p in model_dir.rglob("*") if p.is_file() and p.suffix.lower() in SUFFIXES
             and p.name not in PROTECTED and "build" not in p.relative_to(model_dir).parts}
    explicit = os.environ.get("DOSI_MODEL")
    if explicit:
        paths.add((project / explicit).resolve())
    args = payload.get("tool_input") or payload.get("input") or {}
    file = args.get("file_path") or args.get("path")
    if file and Path(file).name in {"model.yaml", "model.yml", "model.json"}:
        paths.add((project / file).resolve())
    command = args.get("command") or payload.get("command") or ""
    # Explicit CLI model arguments and structured patch targets are supported.
    # Arbitrary shell programs remain outside the host's file-tool contract.
    try:
        words = shlex.split(command)
    except ValueError:
        words = []
    for index, word in enumerate(words):
        if word == "--model" and index + 1 < len(words):
            paths.add((project / words[index + 1]).resolve())
        elif word.startswith("--model="):
            paths.add((project / word.split("=", 1)[1]).resolve())
    for file in re.findall(r"^\*\*\* (?:Add|Update) File: (.+)$", command, re.M):
        path = (project / file).resolve()
        if path.is_relative_to(model_dir.resolve()):
            paths.add(path)
    return sorted(p for p in paths if p.is_file() and p.suffix.lower() in SUFFIXES and p.name not in PROTECTED)


def signature(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    payload = json.load(sys.stdin)
    project = Path(payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()).resolve()
    after = "--after" in sys.argv
    cache_dir = Path(os.environ.get("DOSI_MODEL_STATE_DIR") or (Path(tempfile.gettempdir()) / "dosi-model-state"))
    cache_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    key = hashlib.sha256(str(project).encode()).hexdigest()
    cache_file = cache_dir / (key + ".json")
    try:
        cache = json.loads(cache_file.read_text())
    except (OSError, ValueError):
        cache = {}
    changed, problems = [], []
    version = subprocess.run([str(ROOT / "bin/dosi"), "--version"], cwd=project,
                             capture_output=True, text=True, timeout=10).stdout.strip()
    env = {k: v for k, v in os.environ.items() if k not in {"DOSI_MODEL", "DOSI_ONTOLOGY", "DOSI_MAPPING"}}
    for path in targets(payload, project):
        before = signature(path)
        cached = cache.get(str(path))
        if isinstance(cached, dict) and cached.get("signature") == before and cached.get("version") == version:
            if cached.get("error"):
                problems.append(cached["error"])
            continue
        original = before
        for _ in range(3):
            proc = subprocess.run([str(ROOT / "bin/dosi"), "--model", str(path), "--format", "json", "validate"],
                                  cwd=project, env=env, capture_output=True, text=True, timeout=50)
            if proc.returncode == 3:
                print("Dosi is still installing. Retry the model file operation when installation finishes.", file=sys.stderr)
                return 2
            current = signature(path)
            if current == before:
                # Cache failures too so an invalid file remains editable. Its next
                # content change always triggers another native load.
                error = f"{path}: {proc.stderr or proc.stdout}" if proc.returncode else ""
                cache[str(path)] = {"signature": current, "version": version, "error": error}
                if error:
                    problems.append(error)
                break
            before = current
        else:
            print(f"{path} changed repeatedly during model loading; read it again.", file=sys.stderr)
            return 2
        if current != original:
            changed.append(str(path))
    with tempfile.NamedTemporaryFile(mode="w", dir=cache_dir, delete=False) as tmp:
        json.dump(cache, tmp)
    os.replace(tmp.name, cache_file)
    if changed and not after and payload.get("tool_name") in WRITES:
        print("Dosi refreshed these model files. Read their current contents before editing or rerunning the command: "
              + ", ".join(changed), file=sys.stderr)
        return 2
    if problems:
        message = "Model validation found errors; read the file to repair them:\n" + "\n".join(problems)
        if after:
            print(message, file=sys.stderr)
            return 2
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": message}}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"Dosi model loading failed: {exc}. Retry before using model fields.", file=sys.stderr)
        sys.exit(2)
