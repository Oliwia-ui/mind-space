import { render, screen } from "@testing-library/react";
import App from "./App";

describe("Mind Space shell", () => {
  it("identifies the product and its organising action", () => {
    render(<App />);

    expect(screen.getByRole("heading", { name: "Mind Space" })).toBeVisible();
    expect(
      screen.getByRole("button", { name: "MAKE IT MAKE SENSE" }),
    ).toBeEnabled();
  });
});
