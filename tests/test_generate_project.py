"""Offline integration tests; all generated projects and HOME live in a temp dir."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/generate_project.sh"


class GenerateProjectTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="generate-project-")
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        home = self.work / "home"
        home.mkdir()
        (home / ".gitignore_global").write_text(".env\n")
        tools = self.work / "tools"
        tools.mkdir()
        # Block the license download; no GitHub or optional global helper runs.
        (tools / "curl").write_text("#!/bin/sh\nexit 1\n")
        (tools / "curl").chmod(0o755)
        self.env = dict(
            os.environ,
            HOME=str(home),
            PATH=f"{tools}:/usr/bin:/bin",
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL="/dev/null",
            GIT_AUTHOR_NAME="Test",
            GIT_AUTHOR_EMAIL="test@example.invalid",
            GIT_COMMITTER_NAME="Test",
            GIT_COMMITTER_EMAIL="test@example.invalid",
            GENERATE_PROJECT_CODEX_TEMPLATE=str(ROOT / "tpl/codex"),
        )

    def run_command(self, args, cwd=None, ok=True):
        result = subprocess.run(
            args, cwd=cwd or self.work, env=self.env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result.stdout

    def generate(self, *args, ok=True):
        return self.run_command(["/bin/bash", str(SCRIPT), *args], ok=ok)

    def snapshot(self, directory):
        return {
            str(p.relative_to(directory)): p.read_bytes()
            for p in directory.rglob("*") if p.is_file()
        }

    def test_new_projects_keep_codex_out_of_initial_commit(self):
        for stack in ("node", "python", "terraform", "docker", "go", ""):
            with self.subTest(stack=stack):
                name = "app-" + (stack or "generic")
                args = ["--project", name, "--no-github", "--no-claude", "--prefix", "demo"]
                if stack:
                    args += ["--type", stack]
                self.generate(*args)
                project = self.work / name
                instructions = (project / "AGENTS.md").read_text()
                self.assertIn("`demo-`", instructions)
                self.assertIn(f"Stack: {stack or 'generic'}.", instructions)
                self.assertNotIn("__COMMANDS__", instructions)
                self.assertTrue((project / ".agents/skills/project-checks/SKILL.md").is_file())
                self.assertTrue((project / ".codex/config.toml").is_file())
                tracked = self.run_command(["git", "ls-files"], cwd=project).splitlines()
                self.assertIn("README.md", tracked)
                self.assertFalse(any(p.startswith((".agents/", ".codex/", "AGENTS")) for p in tracked))
                self.run_command(["git", "check-ignore", "AGENTS.md", "AGENTS.override.md", ".codex/config.toml", ".agents/skills/project-checks/SKILL.md"], cwd=project)
                if stack == "go":
                    self.assertFalse((project / ".dockerignore").exists())
                else:
                    self.assertIn("AGENTS.md", (project / ".dockerignore").read_text())

    def test_retrofit_preserves_edits_and_repairs_skills(self):
        project = self.work / "existing project"
        project.mkdir()
        self.run_command(["git", "init", "-q"], cwd=project)
        self.generate("--codex-only", str(project), "--type", "node")
        (project / ".codex/config.toml").write_text("# user settings\n")
        skill = project / ".agents/skills/project-checks"
        (skill / "local.txt").write_text("user edit")
        self.generate("--codex-only", str(project), "--prefix", "demo")
        before = self.snapshot(project)
        self.generate("--codex-only", str(project), "--prefix", "demo")
        self.assertEqual(before, self.snapshot(project))
        self.assertEqual((skill / "local.txt").read_text(), "user edit")
        self.generate("--codex-only", str(project), "--prefix", "other")
        self.assertIn("`demo-`", (project / "AGENTS.md").read_text())
        scoped = project / ".agents/skills/scoped-resources"
        import shutil
        shutil.rmtree(scoped)
        scoped.symlink_to(self.work / "missing-skill")
        self.generate("--codex-only", str(project))
        self.assertTrue((scoped / "SKILL.md").is_file())
        self.assertFalse(scoped.is_symlink())
        shutil.rmtree(scoped)
        scoped.write_text("symlink stub")
        self.generate("--codex-only", str(project))
        self.assertTrue((scoped / "SKILL.md").is_file())
        self.run_command(["git", "check-ignore", "AGENTS.md", ".codex/config.toml"], cwd=project)
        self.assertFalse((project / ".claude").exists())
        self.assertEqual(self.run_command(["git", "ls-files"], cwd=project), "")

    def test_override_and_custom_templates(self):
        project = self.work / "project"
        project.mkdir()
        (project / "AGENTS.override.md").write_text("Existing override\n")
        self.generate("--codex-only", str(project), "--prefix", "demo")
        self.assertFalse((project / "AGENTS.md").exists())
        self.assertEqual((project / "AGENTS.override.md").read_text(), "Existing override\n")
        template = self.work / "custom template"
        template.mkdir()
        (template / "AGENTS.md.tpl").write_text("# __PROJECT__\n- Stack: __TYPE__.\n__PREFIX__\n__COMMANDS__\n")
        skills = template / "skills"
        skills.mkdir()
        (skills / "checks").symlink_to(ROOT / "tpl/codex/skills/project-checks")
        output = self.work / "other project"
        output.mkdir()
        self.generate("--codex-only", str(output), "--codex-template", "custom template", "--type", "go")
        self.assertIn("make test", (output / "AGENTS.md").read_text())
        self.assertFalse((output / ".agents/skills/checks").is_symlink())
        self.assertTrue((output / ".agents/skills/checks/SKILL.md").is_file())

    def test_opt_out_fallback_and_invalid_arguments(self):
        self.generate("--project", "plain", "--no-github", "--no-codex", "--no-claude")
        self.assertFalse((self.work / "plain/AGENTS.md").exists())
        self.assertFalse((self.work / "plain/.agents").exists())
        self.generate("--codex-only", str(self.work / "plain"), "--codex-template", "missing", "--type", "python")
        self.assertIn("python app.py", (self.work / "plain/AGENTS.md").read_text())
        self.generate("--codex-only", "--no-codex", ok=False)
        self.generate("--codex-only", "--claude-only", ok=False)
        self.generate("--codex-only", "--prefix", "bad!", ok=False)

    def test_claude_mode_still_works_independently(self):
        project = self.work / "claude"
        project.mkdir()
        self.generate("--claude-only", str(project), "--claude-template", "missing", "--prefix", "demo")
        self.assertIn("`demo-`", (project / ".claude/CLAUDE.md").read_text())
        self.assertFalse((project / "AGENTS.md").exists())

    def test_prefix_compatibility_with_older_instructions_and_templates(self):
        project = self.work / "older project"
        project.mkdir()
        (project / "AGENTS.md").write_text("# Existing\n- Stack: node.\nCustom instructions.\n")
        # The folder may follow other flags, as in the Claude retrofit interface.
        self.generate("--codex-only", "--prefix", "vcr-", str(project))
        instructions = (project / "AGENTS.md").read_text()
        self.assertIn("`vcr-`", instructions)
        self.assertIn("Custom instructions.", instructions)
        self.assertEqual(instructions.count("Resource prefix:"), 1)
        before = self.snapshot(project)
        self.generate("--codex-only", "--prefix", "vcr", str(project))
        self.assertEqual(before, self.snapshot(project))
        template = self.work / "old-template"
        template.mkdir()
        (template / "AGENTS.md.tpl").write_text("# __PROJECT__\n- Stack: __TYPE__.\n__COMMANDS__\n")
        other = self.work / "old-template-project"
        other.mkdir()
        self.generate("--codex-only", str(other), "--codex-template", str(template), "--prefix", "vcr")
        self.assertIn("`vcr-`", (other / "AGENTS.md").read_text())
        for prefix in ("VCR", "Bad!", "a123456789012", "1abc"):
            self.generate("--project", "invalid", "--no-github", "--prefix", prefix, ok=False)
            self.assertFalse((self.work / "invalid").exists())


if __name__ == "__main__":
    unittest.main()
