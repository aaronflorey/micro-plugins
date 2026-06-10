#!/usr/bin/env bun

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

type PluginName = "format" | "configdel" | "jsonschema";

type PluginRepo = Array<{
  Name: string;
  Description: string;
  Website: string;
  Tags: string[];
  Versions: Array<{
    Version: string;
    Url: string;
    Require?: {
      micro?: string;
    };
  }>;
}>;

const plugins: PluginName[] = ["format", "configdel", "jsonschema"];
const repoBaseUrl = "https://github.com/aaronflorey/micro-plugins/releases/download";

function readVersion(plugin: PluginName): string {
  return readFileSync(join("plugins", plugin, "version.txt"), "utf8").trim();
}

function syncLuaVersion(plugin: PluginName, version: string) {
  const luaPath = join("plugins", plugin, `${plugin}.lua`);
  const lua = readFileSync(luaPath, "utf8");
  const pattern = /^VERSION = ".*"/m;

  if (!pattern.test(lua)) {
    throw new Error(`Missing VERSION line in ${luaPath}`);
  }

  const next = lua.replace(pattern, `VERSION = "${version}"`);

  writeFileSync(luaPath, next);
}

function syncRepoJson(path: string, plugin: PluginName, version: string) {
  const repo = JSON.parse(readFileSync(path, "utf8")) as PluginRepo;
  const latest = repo[0]?.Versions?.[0];

  if (!latest) {
    throw new Error(`Missing latest version in ${path}`);
  }

  latest.Version = version;
  latest.Url = `${repoBaseUrl}/${plugin}-v${version}/${plugin}-${version}.zip`;

  writeFileSync(path, `${JSON.stringify(repo, null, 2)}\n`);
}

for (const plugin of plugins) {
  const version = readVersion(plugin);

  syncLuaVersion(plugin, version);
  syncRepoJson(join("plugins", plugin, "repo.json"), plugin, version);

  if (plugin === "format") {
    syncRepoJson("repo.json", plugin, version);
  }
}
