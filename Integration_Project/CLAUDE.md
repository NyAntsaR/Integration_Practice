# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Salesforce DX project (`Integration_Project`). Source-driven Salesforce development: metadata lives as source files under `force-app/`, tracked in git, and synced to a Salesforce org via the Salesforce CLI (`sf`). The project is currently a fresh scaffold — `force-app/main/default/*` subdirectories (classes, triggers, lwc, aura, objects, flexipages, etc.) exist but are empty.

- Default package directory: `force-app` (see `sfdx-project.json`)
- Source API version: 68.0
- No namespace

## Commands

### Salesforce CLI (org/metadata)

- `sf org login web` — authorize an org
- `sf org create scratch -f config/project-scratch-def.json` — create a scratch org (requires Dev Hub)
- `sf project deploy start` — deploy local metadata to the authorized org
- `sf project retrieve start` — pull metadata from the org into `force-app/`
- `sf apex run --file scripts/apex/hello.apex` — run an anonymous Apex script
- `sf apex test run` — run Apex tests in the org
- `sf data query --file scripts/soql/account.soql` — run a SOQL query
- `sf template generate <artifact>` — scaffold a new component (Apex class, LWC, trigger, etc.)

### Node tooling (LWC/Aura JS)

- `npm run lint` — ESLint over `**/{aura,lwc}/**/*.js`
- `npm run test:unit` — run LWC Jest tests (`sfdx-lwc-jest`)
- `npm run test:unit:watch` — Jest in watch mode
- `npm run test:unit:coverage` — Jest with coverage
- To run a single LWC test file: `npx sfdx-lwc-jest force-app/main/default/lwc/<componentName>/__tests__/<file>.test.js`
- `npm run prettier` — format all supported files (`.cls,.cmp,.component,.css,.html,.js,.json,.md,.page,.trigger,.xml,.yaml,.yml`)
- `npm run prettier:verify` — check formatting without writing

### Git hooks

A pre-commit hook (via Husky, `.husky/pre-commit`) runs `lint-staged`, which on staged files:
- Runs Prettier (all supported metadata/code file types)
- Runs ESLint on `**/{aura,lwc}/**/*.js`
- Runs Jest (`--bail --findRelatedTests --passWithNoTests`) on changed files under `**/lwc/**`

## Architecture notes

- **Apex** goes in `force-app/main/default/classes` and `force-app/main/default/triggers`.
- **Lightning Web Components** go in `force-app/main/default/lwc`; **Aura** components go in `force-app/main/default/aura` — these have separate ESLint configs (`eslint.config.js` applies `@salesforce/eslint-config-lwc` to LWC and `@salesforce/eslint-plugin-aura` to Aura, with locker-service rules for Aura).
- **Custom objects/fields**, **flexipages**, **layouts**, **tabs**, **applications**, **permission sets**, **static resources**, and **content assets** each have their own top-level folder under `force-app/main/default/` following standard SFDX metadata layout.
- `.forceignore` excludes `package.xml`, LWC `jsconfig.json`/`.eslintrc.json`, and `**/__tests__/**` from org push/pull/status — these are local dev-only files and should not round-trip to the org.
- `manifest/package.xml` is a retrieve manifest (currently wildcards ApexClass, ApexComponent, ApexPage, ApexTestSuite, ApexTrigger, AuraDefinitionBundle, LightningComponentBundle, StaticResource) — update it when you need to retrieve additional metadata types from an org.
- `scripts/apex/` and `scripts/soql/` hold ad hoc anonymous Apex and SOQL scripts for manual testing against an org (not deployed metadata).
