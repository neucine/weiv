import { defineConfig } from "cypress";

export default defineConfig({
  video: false,
  screenshotOnRunFailure: true,
  screenshotsFolder: "test/cypress/assets/screenshots",
  e2e: {
    baseUrl: process.env.CYPRESS_BASE_URL ?? "http://127.0.0.1:3001",
    specPattern: "test/cypress/assets/e2e/**/*.cy.{js,ts}",
    supportFile: false,
  },
});
