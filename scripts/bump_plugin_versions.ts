#!/usr/bin/env bun

import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = join(import.meta.dir, "..");
const pluginsDir = join(repoRoot, "plugins");

type BumpLevel = "major" | "minor" | "patch";

function runGit(args: string[]): string {
  return execFileSync("git", args, { cwd: repoRoot, encoding: "utf-8" }).trim();
}

function bumpVersion(version: string, level: BumpLevel): string {
  const [major, minor, patch] = version.split(".").map((value) => Number.parseInt(value, 10));
  if (level === "major") {
    return `${major + 1}.0.0`;
  }
  if (level === "minor") {
    return `${major}.${minor + 1}.0`;
  }
  return `${major}.${minor}.${patch + 1}`;
}

function changedPluginsFromIndex(): Set<string> {
  const changed = runGit(["diff", "--cached", "--name-only"]);
  const pluginFiles = new Map<string, boolean>();

  for (const path of changed.split(/\r?\n/)) {
    const parts = path.split("/");
    if (parts.length < 2 || parts[0] !== "plugins") continue;

    const plugin = parts[1];
    // Only version-related files get the version-only check
    if (path.endsWith("repo.json") || path.endsWith(".lua")) {
      if (!pluginFiles.has(plugin)) {
        const diff = runGit(["diff", "--cached", "--", `plugins/${plugin}/`]);
        const changeLines = diff.split(/\r?\n/).filter((l) => l.startsWith("+") || l.startsWith("-"));
        const onlyVersion = changeLines.length > 0 && changeLines.every((l) =>
          /^[+-]\s*("Version":\s*"[^"]*"|VERSION\s*=\s*"[^"]*")/.test(l)
        );
        pluginFiles.set(plugin, !onlyVersion);
      }
    } else {
      pluginFiles.set(plugin, true);
    }
  }

  return new Set(Array.from(pluginFiles.entries()).filter(([, v]) => v).map(([k]) => k));
}

function updatePluginLuaVersion(plugin: string, newVersion: string): string | null {
  const pluginDir = join(pluginsDir, plugin);
  const entries = readdirSync(pluginDir, { withFileTypes: true });
  const luaFiles = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".lua"))
    .map((entry) => join(pluginDir, entry.name))
    .sort();

  for (const luaFile of luaFiles) {
    const content = readFileSync(luaFile, "utf-8");
    const updated = content.replace(
      /^VERSION\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"/m,
      `VERSION = "${newVersion}"`,
    );
    if (updated !== content) {
      writeFileSync(luaFile, updated, "utf-8");
      return luaFile;
    }
  }

  return null;
}

function updatePluginRepoJson(plugin: string, newVersion: string): void {
  const path = join(pluginsDir, plugin, "repo.json");
  const data = JSON.parse(readFileSync(path, "utf-8")) as Array<Record<string, unknown>>;

  if (data.length > 0) {
    const versions = data[0].Versions;
    if (Array.isArray(versions) && versions.length > 0) {
      (versions[0] as Record<string, unknown>).Version = newVersion;
    }
  }

  writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`, "utf-8");
}

function updateRepoJsonVersions(plugins: Set<string>, level: BumpLevel): Map<string, string> {
  const bumped = new Map<string, string>();

  for (const plugin of plugins) {
    const perPluginPath = join(pluginsDir, plugin, "repo.json");
    if (!existsSync(perPluginPath)) continue;

    const data = JSON.parse(readFileSync(perPluginPath, "utf-8")) as Array<Record<string, unknown>>;
    if (data.length === 0) continue;

    const versions = data[0].Versions;
    if (!Array.isArray(versions) || versions.length === 0) continue;

    const current = (versions[0] as Record<string, unknown>).Version;
    if (typeof current !== "string") continue;

    const newVersion = bumpVersion(current, level);
    bumped.set(plugin, newVersion);
  }

  for (const [plugin, newVersion] of bumped) {
    updatePluginRepoJson(plugin, newVersion);
  }

  return bumped;
}

function main(): number {
  const changedPlugins = changedPluginsFromIndex();
  if (changedPlugins.size === 0) {
    return 0;
  }

  const bumped = updateRepoJsonVersions(changedPlugins, "patch");
  if (bumped.size === 0) {
    return 0;
  }

  for (const [plugin, newVersion] of bumped.entries()) {
    const luaFile = updatePluginLuaVersion(plugin, newVersion);
    if (!luaFile) {
      console.log(`lefthook: warning: no VERSION entry found for plugin '${plugin}'`);
    }
  }

  const details = Array.from(bumped.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, version]) => `${name} -> ${version}`)
    .join(", ");
  console.log(`lefthook: bumped plugin versions (patch): ${details}`);
  return 0;
}

process.exit(main());
