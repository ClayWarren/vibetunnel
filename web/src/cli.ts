#!/usr/bin/env node
// Entry point for the server - imports the modular server which starts automatically

// Suppress xterm.js errors globally - must be before any other imports
import { suppressXtermErrors } from './shared/suppress-xterm-errors.js';

suppressXtermErrors();

import { startVibeTunnelForward } from './server/fwd.js';
import { startVibeTunnelServer } from './server/server.js';
import { closeLogger, createLogger, initLogger, VerbosityLevel } from './server/utils/logger.js';
import { parseVerbosityFromEnv } from './server/utils/verbosity-parser.js';
import { VERSION } from './server/version.js';

// Initialize logger before anything else
// Parse verbosity from environment variables
const verbosityLevel = parseVerbosityFromEnv();

// Check for legacy debug mode (for backward compatibility with initLogger)
const debugMode = process.env.VIBETUNNEL_DEBUG === '1' || process.env.VIBETUNNEL_DEBUG === 'true';

initLogger(debugMode, verbosityLevel);
const logger = createLogger('cli');

// Source maps are only included if built with --sourcemap flag

// Prevent double execution in SEA context where require.main might be undefined
// Use a global flag to ensure we only run once
interface GlobalWithVibetunnel {
  __vibetunnelStarted?: boolean;
}

const globalWithVibetunnel = global as unknown as GlobalWithVibetunnel;

if (globalWithVibetunnel.__vibetunnelStarted) {
  process.exit(0);
}
globalWithVibetunnel.__vibetunnelStarted = true;

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  logger.error('Uncaught exception:', error);
  logger.error('Stack trace:', error.stack);
  closeLogger();
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled rejection at:', promise, 'reason:', reason);
  if (reason instanceof Error) {
    logger.error('Stack trace:', reason.stack);
  }
  closeLogger();
  process.exit(1);
});

// Only execute if this is the main module (or in SEA/bundled context where require.main is undefined)
// In bundled builds, both module.parent and require.main are undefined
// In npm package context, check if we're the actual CLI entry point
const isMainModule =
  !module.parent &&
  (require.main === module ||
    require.main === undefined ||
    (require.main?.filename?.endsWith('/vibetunnel-cli') ?? false));

if (isMainModule) {
  if (process.argv[2] === 'version') {
    console.log(`VibeTunnel Server v${VERSION}`);
    process.exit(0);
  } else if (process.argv[2] === 'fwd') {
    startVibeTunnelForward(process.argv.slice(3)).catch((error) => {
      logger.error('Fatal error:', error);
      closeLogger();
      process.exit(1);
    });
  } else {
    // Show startup message at INFO level or when debug is enabled
    if (verbosityLevel !== undefined && verbosityLevel >= VerbosityLevel.INFO) {
      logger.log('Starting VibeTunnel server...');
    }
    startVibeTunnelServer();
  }
}
