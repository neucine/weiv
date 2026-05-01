import { defineConfig } from "cypress";

export default defineConfig({
  video: false,
  screenshotOnRunFailure: true,
  e2e: {
    baseUrl: process.env.CYPRESS_BASE_URL ?? "http://127.0.0.1:3001",
    specPattern: "cypress/e2e/**/*.cy.{js,ts}",
    supportFile: false,
  },
});
