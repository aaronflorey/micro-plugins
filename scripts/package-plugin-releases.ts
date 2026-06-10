#!/usr/bin/env bun

import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { $ } from "bun";

const allPlugins = ["format", "configdel", "jsonschema"];
const requestedPlugins = process.argv.slice(2);
const plugins = requestedPlugins.length > 0 ? requestedPlugins : allPlugins;

for (const plugin of plugins) {
  if (!allPlugins.includes(plugin)) {
    throw new Error(`Unknown plugin: ${plugin}`);
  }

  const pluginDir = join("plugins", plugin);
  const version = readFileSync(join(pluginDir, "version.txt"), "utf8").trim();

  if (typeof version !== "string" || version.length === 0) {
    throw new Error(`Missing version in ${pluginDir}/version.txt`);
  }

  const outputDir = resolve("dist", "plugin-releases");
  const outputPath = resolve(outputDir, `${plugin}-${version}.zip`);
  const stageRoot = mkdtempSync(join(tmpdir(), `${plugin}-`));
  const archiveRoot = join(stageRoot, `${plugin}-${version}`);

  mkdirSync(outputDir, { recursive: true });

  cpSync(pluginDir, archiveRoot, {
    recursive: true,
    filter: (source) => !source.endsWith(".zip"),
  });

  try {
    if (existsSync(outputPath)) {
      rmSync(outputPath);
    }

    await $`zip -qry ${outputPath} ${plugin}-${version}`.cwd(stageRoot);
    console.log(`${plugin}: wrote ${outputPath}`);
  } finally {
    rmSync(stageRoot, { recursive: true, force: true });
  }
}
