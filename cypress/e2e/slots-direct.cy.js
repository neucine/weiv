describe("Slot composition direct bundle", () => {
  beforeEach(() => {
    cy.visit("/");
  });

  it("renders projected named-slot content", () => {
    cy.get('[data-test="header-title"]').should("have.text", "Initial");
    cy.get('[data-test="header-eyebrow"]').should("contain.text", "Updated 0");
  });

  it("renders projected default-slot content", () => {
    cy.get('[data-test="body"]').should("have.text", "Body 0");
  });

  it("updates projected slot interpolations when parent state changes", () => {
    cy.get('[data-test="header-title"]').then(($el) => {
      const before = $el[0];
      cy.get('[data-test="bump"]').click();
      cy.get('[data-test="header-title"]').should("have.text", "Bumped 1");
      cy.get('[data-test="header-title"]').then(($after) => {
        // Same element node — proves no remount
        expect($after[0]).to.equal(before);
      });
      cy.get('[data-test="body"]').should("have.text", "Body 1");
      cy.get('[data-test="header-eyebrow"]').should("contain.text", "Updated 1");
    });
  });

  it("updates non-slot interpolations in step with slot interpolations", () => {
    cy.get('[data-test="bump"]').click();
    cy.get('[data-test="bump"]').click();
    cy.get('[data-test="header-title"]').should("have.text", "Bumped 2");
    cy.get('[data-test="body"]').should("have.text", "Body 2");
    cy.get('[data-test="header-eyebrow"]').should("contain.text", "Updated 2");
  });
});
