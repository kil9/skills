#!/usr/bin/env node

// Local policy: image generation must remain on the harness-native path so it
// uses included subscription quota and never switches to API billing.
console.error(
  'generate-image: disabled by local policy; use the harness-native image generation tool.',
);
process.exit(1);
