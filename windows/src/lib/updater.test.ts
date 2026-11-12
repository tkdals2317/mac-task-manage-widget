import { describe, expect, it } from "vitest";
import { compareVersions } from "./updater";

describe("compareVersions", () => {
  it("compares numerically", () => {
    expect(compareVersions("1.2.10", "1.2.9")).toBe(1);
    expect(compareVersions("0.1.0", "0.1.0")).toBe(0);
    expect(compareVersions("0.1", "0.1.1")).toBe(-1);
  });
});
