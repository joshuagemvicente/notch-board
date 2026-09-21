export const site = {
  name: "NotchBoard",
  tagline: "Boards at the notch.",
  description:
    "A macOS menu bar app that ranks your boards by what you’re working on right now — pinned, due, recent, and the repo in focus.",
  downloadUrl:
    "https://github.com/joshuagemvicente/NotchBoard/releases/latest",
  githubUrl: "https://github.com/joshuagemvicente/NotchBoard",
  requirements: "macOS 14+",
  versionLabel: "Open source · Free",
} as const;

export const providers = [
  { name: "Trello", color: "#0079BF" },
  { name: "GitHub Projects", color: "#24292F" },
  { name: "Linear", color: "#5E6AD2" },
  { name: "Jira", color: "#1D7AFC" },
  { name: "Azure DevOps", color: "#0078D4" },
] as const;
