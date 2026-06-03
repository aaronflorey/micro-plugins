#!/usr/bin/env bun

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { $, argv } from "bun";
import { CommitParser } from "conventional-commits-parser";

if (process.env.BUMP_PLUGIN_VERSION_AMENDING === "1") {
  process.exit(0);
}

const commitMessage = await readFileSync(argv[2], "utf8");
const parser = new CommitParser();

function getBumpType(): string | null {
  const result = parser.parse(commitMessage);
  return result.type;
}

function getBumpVersion(version: string, bumpType: string): string {
  const [major, minor, patch] = version.split(".").map(Number);

  if ([major, minor, patch].some(Number.isNaN)) {
    throw new Error(`Invalid semver version: ${version}`);
  }

  if (["feat"].includes(bumpType)) {
    return `1.${minor + 1}.0`;
  }

  return `1.${minor}.${patch + 1}`;
}

const bumpType = getBumpType();
if (!bumpType) {
  console.log("No conventional commit message found.");
  process.exit(1);
}

const changedFiles = (await $`git diff-index --cached --name-only HEAD`.text())
  .trim()
  .split("\n")
  .filter(Boolean);

const changedPlugins = new Set(); //
for (const file of changedFiles) {
  const match = file.match(/^plugins\/([^/]+)\/.+\.lua$/);
  if (match) changedPlugins.add(match[1]);
}

if (changedPlugins.size === 0) {
  console.log("no plugins");
  console.log({ changedFiles });
  process.exit(1);
}

for (const plugin of changedPlugins) {
  const repoPath = `plugins/${plugin}/repo.json`;
  const pluginPath = `plugins/${plugin}/${plugin}.lua`;

  if (!existsSync(repoPath)) {
    console.warn(`Skipping ${plugin}: missing ${repoPath}`);
    continue;
  }

  const repo = JSON.parse(readFileSync(repoPath, "utf8"));
  const pluginMeta = repo[0];
  const latest = pluginMeta?.Versions?.[0];

  if (!latest?.Version) {
    throw new Error(`Invalid repo.json structure: ${repoPath}`);
  }

  const newVersion = getBumpVersion(latest.Version, bumpType);

  if (pluginMeta.Versions.some((v) => v.Version === newVersion)) {
    continue;
  }

  pluginMeta.Versions.unshift({
    ...latest,
    Version: newVersion,
  });

  writeFileSync(repoPath, `${JSON.stringify(repo, null, 2)}\n`);

  if (!existsSync(pluginPath)) {
    await $`git add ${repoPath}`;

    continue;
  }

  const pluginSrc = readFileSync(pluginPath, "utf8");
  const lines = pluginSrc.split(/\r?\n/);
  let updatedPluginVersion = false;

  for (const index in lines) {
    if (/^VERSION\s*=\s*"\d+\.\d+\.\d+"$/.test(lines[index])) {
      lines[index] = `VERSION = "${newVersion}"`;
      updatedPluginVersion = true;
    }
  }

  if (updatedPluginVersion) {
    writeFileSync(pluginPath, lines.join("\n"));
    await $`git add ${repoPath} ${pluginPath}`;
  } else {
    await $`git add ${repoPath}`;
  }

  console.log(`${plugin}: ${latest.Version} -> ${newVersion}`);
}

const staged = await $`git diff --cached --name-only`.text();

if (staged.trim()) {
  await $`git commit --amend --no-edit --no-verify`.env({
    ...process.env,
    BUMP_PLUGIN_VERSION_AMENDING: "1",
  });
  process.exit(1);
}
