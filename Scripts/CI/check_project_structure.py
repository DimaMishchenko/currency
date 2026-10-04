import collections
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET


def check(root):
    workspace = ET.parse(root / "Currency.xcworkspace/contents.xcworkspacedata")
    projects = [entry.attrib["location"] for entry in workspace.iter("FileRef")]
    failures = []
    if projects != ["group:Currency.xcodeproj"]:
        failures.append(f"Unexpected workspace projects: {projects}")
    project = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-",
        str(root / "Currency.xcodeproj/project.pbxproj"),
    ]))
    objects = project["objects"]
    references = []
    synchronized = []

    def visit(identifier, parent):
        entry = objects[identifier]
        source_tree = entry.get("sourceTree", "<group>")
        if source_tree == "BUILT_PRODUCTS_DIR":
            return
        if source_tree == "SOURCE_ROOT":
            parent = root
        path = (parent / entry.get("path", "")).resolve()
        kind = entry["isa"]
        if kind in {"PBXGroup", "PBXVariantGroup"}:
            for child in entry.get("children", []):
                visit(child, path)
        elif kind == "PBXFileSystemSynchronizedRootGroup":
            synchronized.append(path)
        elif kind == "PBXFileReference":
            references.append(path)

    visit(objects[project["rootObject"]]["mainGroup"], root)
    for path, count in collections.Counter(references + synchronized).items():
        if count > 1:
            failures.append(f"Duplicate navigator path: {path.relative_to(root)}")
    for index, folder in enumerate(synchronized):
        for other in synchronized[index + 1:]:
            if folder in other.parents or other in folder.parents:
                failures.append(f"Overlapping synchronized folders: {folder.relative_to(root)}, {other.relative_to(root)}")
    for path in references:
        if any(folder == path or folder in path.parents for folder in synchronized):
            failures.append(f"Explicit reference overlaps synchronized folder: {path.relative_to(root)}")
    directories = synchronized + [path for path in references if path.is_dir()]
    tracked = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"]).decode().split("\0")
    for name in filter(None, tracked):
        path = root / name
        coverage = int(path in references) + sum(folder in path.parents for folder in directories)
        if coverage == 0:
            failures.append(f"Tracked file missing from navigator: {name}")
        elif coverage > 1:
            failures.append(f"Tracked file appears more than once in navigator: {name}")
    return failures


if __name__ == "__main__":
    repository = Path(__file__).resolve().parents[2]
    errors = check(repository)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)
    print("Validated one Currency project, complete tracked-file coverage, and no duplicate navigator paths")
