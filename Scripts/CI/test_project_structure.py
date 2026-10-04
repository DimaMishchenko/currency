import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from check_project_structure import check


class ProjectStructureTests(unittest.TestCase):
    def inspect(self, entries, tracked):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            workspace = root / "Currency.xcworkspace"
            workspace.mkdir()
            (workspace / "contents.xcworkspacedata").write_text(
                '<Workspace><FileRef location="group:Currency.xcodeproj"/></Workspace>'
            )
            objects = {
                "project": {"mainGroup": "main"},
                "main": {"isa": "PBXGroup", "children": list(entries)},
                **entries,
            }
            project = {"rootObject": "project", "objects": objects}
            with patch("check_project_structure.subprocess.check_output", side_effect=[
                json.dumps(project).encode(), "\0".join(tracked).encode(),
            ]):
                return check(root)

    def folder(self, path):
        return {"isa": "PBXFileSystemSynchronizedRootGroup", "path": path}

    def file(self, path):
        return {"isa": "PBXFileReference", "path": path}

    def test_owned_folder_covers_files(self):
        errors = self.inspect({"sources": self.folder("Features/Home/Sources")},
                              ["Features/Home/Sources/Home/Model.swift"])
        self.assertEqual(errors, [])

    def test_nested_synchronized_folders_are_rejected_even_when_empty(self):
        errors = self.inspect({
            "sources": self.folder("Apps/Currency/App/Sources"),
            "composition": self.folder("Apps/Currency/App/Sources/Composition"),
        }, [])
        self.assertTrue(any("Overlapping synchronized folders" in error for error in errors))

    def test_explicit_file_inside_owned_folder_is_rejected(self):
        errors = self.inspect({
            "sources": self.folder("Features/Home/Sources"),
            "model": self.file("Features/Home/Sources/Home/Model.swift"),
        }, ["Features/Home/Sources/Home/Model.swift"])
        self.assertTrue(any("Explicit reference overlaps" in error for error in errors))
        self.assertTrue(any("appears more than once" in error for error in errors))

    def test_missing_supporting_file_is_rejected(self):
        errors = self.inspect({}, ["Features/Home/README.md"])
        self.assertIn("Tracked file missing from navigator: Features/Home/README.md", errors)

    def test_duplicate_explicit_file_is_rejected(self):
        errors = self.inspect({
            "first": self.file("README.md"), "second": self.file("README.md"),
        }, ["README.md"])
        self.assertIn("Duplicate navigator path: README.md", errors)


if __name__ == "__main__":
    unittest.main()
