import { describe, expect, it, vi } from "vitest";

vi.mock("./http", () => ({ requestText: vi.fn() }));
import { normalize, parse } from "./linkTitle";

describe("linkTitle", () => {
  it("엔티티와 공백", () => {
    const html = "<html><HEAD><TITLE lang=\"ko\">\n  A &amp; B  &lt;c&gt;\n &quot;d&quot; &#39;e&#39; &#65;  </TITLE></HEAD>";
    expect(parse(html)).toBe("A & B <c> \"d\" 'e' A");
  });
  it("&amp; 를 두 번 풀지 않는다", () => expect(parse("<title>&amp;lt;</title>")).toBe("&lt;"));
  it("없거나 빈 제목", () => {
    expect(parse("<html></html>")).toBeNull();
    expect(parse("<title>  </title>")).toBeNull();
  });
  it("normalize", () => {
    expect(normalize("example.com/x")).toBe("https://example.com/x");
    expect(normalize(" http://a.io ")).toBe("http://a.io");
    for (const bad of ["not a url", "", "ftp://a.io", "nodot", "javascript:alert(1)"]) expect(normalize(bad)).toBeNull();
    expect(normalize("localhost:3000")).toBe("https://localhost:3000");
  });
});
