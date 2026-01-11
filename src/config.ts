import { config as loadEnv } from "dotenv";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import { resolve } from "path";

interface ServerConfig {
  port: number;
  outputFormat: "yaml" | "json";
  skipImageDownloads?: boolean;
  configSources: {
    port: "cli" | "env" | "default";
    outputFormat: "cli" | "env" | "default";
    envFile: "cli" | "default";
    skipImageDownloads?: "cli" | "env" | "default";
  };
}

interface CliArgs {
  env?: string;
  port?: number;
  json?: boolean;
  "skip-image-downloads"?: boolean;
}

export function getServerConfig(isStdioMode: boolean): ServerConfig {
  // Parse command line arguments
  const argv = yargs(hideBin(process.argv))
    .options({
      env: {
        type: "string",
        description: "Path to custom .env file to load environment variables from",
      },
      port: {
        type: "number",
        description: "Port to run the server on",
      },
      json: {
        type: "boolean",
        description: "Output data from tools in JSON format instead of YAML",
        default: false,
      },
      "skip-image-downloads": {
        type: "boolean",
        description: "Do not register the download_figma_images tool (skip image downloads)",
        default: false,
      },
    })
    .help()
    .version(process.env.NPM_PACKAGE_VERSION ?? "unknown")
    .parseSync() as CliArgs;

  // Load environment variables ASAP from custom path or default
  let envFilePath: string;
  let envFileSource: "cli" | "default";

  if (argv["env"]) {
    envFilePath = resolve(argv["env"]);
    envFileSource = "cli";
  } else {
    envFilePath = resolve(process.cwd(), ".env");
    envFileSource = "default";
  }

  // Override anything auto-loaded from .env if a custom file is provided.
  loadEnv({ path: envFilePath, override: true });

  const config: ServerConfig = {
    port: 3333,
    outputFormat: "json",
    skipImageDownloads: false,
    configSources: {
      port: "default",
      outputFormat: "default",
      envFile: envFileSource,
      skipImageDownloads: "default",
    },
  };

  // Handle PORT
  if (argv.port) {
    config.port = argv.port;
    config.configSources.port = "cli";
  } else if (process.env.PORT) {
    config.port = parseInt(process.env.PORT, 10);
    config.configSources.port = "env";
  }

  // Handle JSON output format
  if (argv.json) {
    config.outputFormat = "json";
    config.configSources.outputFormat = "cli";
  } else if (process.env.OUTPUT_FORMAT) {
    config.outputFormat = process.env.OUTPUT_FORMAT as "yaml" | "json";
    config.configSources.outputFormat = "env";
  }

  // Handle skipImageDownloads
  if (argv["skip-image-downloads"]) {
    config.skipImageDownloads = true;
    config.configSources.skipImageDownloads = "cli";
  } else if (process.env.SKIP_IMAGE_DOWNLOADS === "true") {
    config.skipImageDownloads = true;
    config.configSources.skipImageDownloads = "env";
  }

  // Log configuration sources
  if (!isStdioMode) {
    console.log("\nFigma MCP Server Configuration:");
    console.log(`- ENV_FILE: ${envFilePath} (source: ${config.configSources.envFile})`);
    console.log(`- PORT: ${config.port} (source: ${config.configSources.port})`);
    console.log(
      `- OUTPUT_FORMAT: ${config.outputFormat} (source: ${config.configSources.outputFormat})`,
    );
    console.log(
      `- SKIP_IMAGE_DOWNLOADS: ${config.skipImageDownloads} (source: ${config.configSources.skipImageDownloads})`,
    );
    console.log("\n⚠️  Authentication: All requests must include figmaOAuthToken parameter");
    console.log(); // Empty line for better readability
  }

  return config;
}
