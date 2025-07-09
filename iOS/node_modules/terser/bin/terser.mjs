#!/usr/bin/env node

"use strict";

import "../tools/exit.cjs";

import fs from "fs";
import path from "path";
import program from "commander";

import { _run_cli as run_cli } from "../main.js";

const packageJson= JSON.parse( fs.readFileSync( new URL("./package.json", import.meta.url)));

run_cli({ program, packageJson, fs, path }).catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
