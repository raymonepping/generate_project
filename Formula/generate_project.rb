class GenerateProject < Formula
  desc "Scaffold projects with local Claude Code and Codex workspaces"
  homepage "https://github.com/raymonepping/generate_project"
  url "https://github.com/raymonepping/generate_project/archive/refs/tags/v2.1.0.tar.gz"
  sha256 "917df79b96ced4531d45d690a1ab18c5a4a2053f4b1215374bacbd69da4936d4"
  license "GPL-3.0-only"

  depends_on "bash"
  depends_on "git"

  def install
    libexec.install "bin", "tpl"
    bin.mkpath

    (bin/"generate_project").write <<~SH
      #!/usr/bin/env bash
      exec "#{Formula["bash"].opt_bin}/bash" "#{libexec}/bin/generate_project.sh" "$@"
    SH
    (bin/"generate_project").chmod 0755
  end

  def caveats
    <<~EOS
      Create a project:
        generate_project --project my-app --type node --no-github

      Add Codex to an existing project:
        generate_project --codex-only . --type node

      Codex templates are bundled. Personal overrides may be placed in:
        ~/.config/generate_project/codex/
      Claude templates remain private and are loaded from:
        ~/.config/generate_project/claude/

      Publishing projects requires an authenticated GitHub CLI:
        brew install gh
        gh auth login
    EOS
  end

  test do
    assert_match "--codex-only", shell_output("#{bin}/generate_project --help")
    system bin/"generate_project", "--codex-only", testpath, "--type", "node", "--prefix", "brew"
    assert_match "Stack: node", (testpath/"AGENTS.md").read
    assert_match "`brew-`", (testpath/"AGENTS.md").read
    assert_path_exists testpath/".agents/skills/project-checks/SKILL.md"
    assert_path_exists testpath/".agents/skills/scoped-resources/SKILL.md"
    assert_path_exists testpath/".codex/config.toml"
  end
end
