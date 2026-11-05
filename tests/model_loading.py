"""File-tool hooks using the real CLI; run with DOSI_DEV_BIN_DIR set."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
HISTORICAL = """version: 0.2.0.dev0
semantic_model:
  - name: shop
    datasets:
      - name: orders
        source: orders
        fields:
          - name: amount
            expression: {dialects: [{dialect: ANSI_SQL, expression: amount}]}
    metrics:
      - name: revenue
        expression: {dialects: [{dialect: ANSI_SQL, expression: 'SUM(orders.amount)'}]}
"""


@unittest.skipUnless(os.environ.get("DOSI_DEV_BIN_DIR"), "requires a locally built Dosi CLI")
class ModelLoadingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.project = Path(self.directory.name)
        self.model = self.project / "dosi" / "sales.yaml"
        self.model.parent.mkdir()
        self.model.write_text(HISTORICAL)
        self.env = {
            **os.environ, "CLAUDE_PROJECT_DIR": str(self.project),
            "DOSI_MODEL_STATE_DIR": str(self.project / "cache"),
            "DOSI_PLUGIN_DATA": str(self.project / "plugin-data"),
        }
        for key in ("DOSI_MODEL", "DOSI_MAPPING", "DOSI_ONTOLOGY", "DOSI_SECRETS_ENV"):
            self.env.pop(key, None)

    def hook(self, tool="Read", after=False):
        return subprocess.run(
            ["python3", str(ROOT / "hooks/model-state.py"), *(["--after"] if after else [])],
            input=json.dumps({"tool_name": tool, "tool_input": {"file_path": str(self.model)}, "cwd": str(self.project)}),
            cwd=self.project, env=self.env, text=True, capture_output=True, timeout=60,
        )

    def test_first_read_normalizes_actual_nondefault_target_and_reuses_signature(self):
        result = self.hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("\nname: shop\n", self.model.read_text())
        snapshot = self.model.read_bytes(), self.model.stat().st_mtime_ns
        result = self.hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.model.read_bytes(), self.model.stat().st_mtime_ns), snapshot)
        backups = list(self.model.parent.glob(".*.bak"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), HISTORICAL)

    def test_explicit_model_does_not_load_unrelated_default_companions(self):
        (self.model.parent / "ontology.yaml").write_text("not-a-document: true\n")
        result = subprocess.run(
            [str(ROOT / "bin/dosi"), "--model", str(self.model), "validate"],
            cwd=self.project, env=self.env, text=True, capture_output=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("\nname: shop\n", self.model.read_text())

    def test_first_write_requires_reread_after_native_replacement(self):
        result = self.hook("Edit")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Read their current contents", result.stderr)
        self.assertIn("\nname: shop\n", self.model.read_text())
        self.assertEqual(self.hook("Edit").returncode, 0)

    def test_external_historical_replacement_triggers_a_new_load(self):
        self.assertEqual(self.hook().returncode, 0)
        self.model.write_text(HISTORICAL.replace("name: revenue", "name: gross_revenue"))
        self.assertEqual(self.hook().returncode, 0)
        self.assertIn("\nname: shop\n", self.model.read_text())
        self.assertIn("name: gross_revenue", self.model.read_text())
        self.assertEqual(len(list(self.model.parent.glob(".*.bak"))), 2)

    def test_cached_validation_error_remains_visible_and_repairable(self):
        self.model.write_text(HISTORICAL.replace("SUM(orders.amount)", "SUM(orders.missing)"))
        for _ in range(2):
            result = self.hook()
            self.assertEqual(result.returncode, 0, result.stderr)
            message = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
            self.assertIn("missing", message)
        result = self.hook(after=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("missing", result.stderr)

    def test_readonly_historical_dry_run_preserves_source_and_directory(self):
        self.model.chmod(0o444)
        before = self.model.read_bytes(), self.model.stat().st_mtime_ns
        files = sorted(path.name for path in self.model.parent.iterdir())
        result = subprocess.run(
            [str(ROOT / "bin/dosi-fill-derived"), "--model", str(self.model), "--dry-run"],
            cwd=self.project, env=self.env, text=True, capture_output=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue(json.loads(result.stdout)["dry_run"])
        self.assertEqual((self.model.read_bytes(), self.model.stat().st_mtime_ns), before)
        self.assertEqual(sorted(path.name for path in self.model.parent.iterdir()), files)


if __name__ == "__main__":
    unittest.main()
