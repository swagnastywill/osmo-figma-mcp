# CLAUDE.md

## Project Overview

Figma Developer MCP (figma-developer-mcp) - An MCP server that gives AI coding agents access to Figma design data. Bridges Figma designs and code generation by simplifying Figma API responses for LLM consumption.

Published as `figma-developer-mcp` on npm. Website: https://www.framelink.ai

## Tech Stack

- **Language**: TypeScript 5.7 (strict mode, ES2022, ESM)
- **Runtime**: Node.js 20 (minimum 18.0.0)
- **Package Manager**: pnpm
- **Build**: tsup (ESM output, minified)
- **Test**: Jest with ts-jest
- **Lint/Format**: ESLint + Prettier (100 char width, 2 spaces, double quotes, trailing commas)
- **Versioning**: Changesets

## Key Commands

```bash
pnpm build          # Build to dist/
pnpm dev            # Dev server with watch mode (HTTP on localhost:3333)
pnpm dev:cli        # Dev in stdio mode
pnpm test           # Run Jest tests
pnpm type-check     # tsc --noEmit
pnpm lint           # ESLint
pnpm format         # Prettier
pnpm inspect        # MCP inspector for debugging
```

## Architecture

Two MCP tools:
- `get_figma_data` - Fetches and simplifies Figma design data into structured nodes
- `download_figma_images` - Downloads, processes, and uploads images to S3

Data flow: Figma API → parseAPIResponse → extractFromDesign (tree walk with extractors) → SimplifiedDesign (YAML/JSON)

### Directory Structure

- `src/mcp/` - MCP server setup and tool definitions
- `src/services/` - Figma API client
- `src/extractors/` - Pluggable design data extraction system
- `src/transformers/` - Layout, style, text, effects, component transformers
- `src/utils/` - Logger, fetch retry, image processing, S3 upload
- `src/tests/` - Integration and benchmark tests
- `deployment/` - AWS EC2 deployment scripts

### Key Types

- `SimplifiedNode` - Core output type for extracted design nodes
- `ExtractorFn` - Pluggable functions that modify nodes during tree traversal
- `SimplifiedLayout`, `SimplifiedFill`, `SimplifiedStroke`, `SimplifiedTextStyle`, `SimplifiedEffects`

## Conventions

- **Files**: kebab-case (`get-figma-data-tool.ts`)
- **Functions**: camelCase
- **Types/Interfaces**: PascalCase
- **Constants**: UPPER_SNAKE_CASE
- **Path alias**: `~/*` maps to `./src/*`
- **Barrel exports**: Each directory has `index.ts`
- **Validation**: Zod for runtime schema validation of tool parameters
- **Error handling**: Try-catch with descriptive messages, logger abstraction for HTTP vs CLI

## Philosophy

- Unix philosophy: tools have one job, few arguments
- Server focuses ONLY on design ingestion for AI consumption
- Out of scope: image manipulation, CMS syncing, code generation, third-party integrations
- Prefer CLI args over tool parameters for project-level config

## Environment Variables

- `FIGMA_API_KEY` (required) - Figma PAT or OAuth token
- `PORT` - HTTP server port (default: 3333)
- `OUTPUT_FORMAT` - "yaml" or "json" (default: "json")
- `SKIP_IMAGE_DOWNLOADS` - "true" to hide download tool
- `NODE_ENV` - "cli" for stdio, else HTTP mode
- `AWS_*` - S3 credentials for image uploads
