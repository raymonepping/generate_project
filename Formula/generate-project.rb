class GenerateProject < Formula
  desc "Scaffold projects with local Claude Code and Codex workspaces"
  homepage "https://github.com/raymonepping/generate_project"
  version "2.3.0"
  url "https://github.com/raymonepping/generate_project/archive/refs/tags/v2.3.0.tar.gz"
  sha256 "15522b3c924ff61a05bb4787fbc5f8c73bdf3356e6ae4550ff545ee2940f051c"
  license "GPL-3.0-only"

  depends_on "bash"
  depends_on "git"

  def install
    libexec.install "bin", "tpl", ".version"
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
    project = testpath/"existing"
    project.mkpath
    system bin/"generate_project", "--project", project, "--codex-only", "--type", "node", "--prefix", "brew"
    refute_path_exists testpath/"AGENTS.md"
    assert_match "Stack: node", (project/"AGENTS.md").read
    assert_match "`brew-`", (project/"AGENTS.md").read
    assert_path_exists project/".agents/skills/project-checks/SKILL.md"
    assert_path_exists project/".agents/skills/scoped-resources/SKILL.md"
    assert_path_exists project/".codex/config.toml"

    handwritten = testpath/"handwritten"
    handwritten.mkpath
    (handwritten/"AGENTS.md").write "# Existing\n\n## Operate\n\n- Keep this guidance.\n"
    system bin/"generate_project", "--codex-only", handwritten, "--prefix", "brew"
    assert_match "`brew-`", (handwritten/"AGENTS.md").read
    assert_match "- Keep this guidance.", (handwritten/"AGENTS.md").read
  end
end
