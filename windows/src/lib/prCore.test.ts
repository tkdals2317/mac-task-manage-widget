import { describe, expect, it } from "vitest";
import {
  approval, badgeCount, bitbucketParts, checkoutCommand, classifyHttp, decodeBitbucketPRs, decodeGitHub, facets, filterReviews,
  githubParts, markApproved, mergedSnapshot, notifications, originFromConfig, parseBitbucketRemote, reviewStatus, safeNext, snapshot,
  sortMine, sortReviewRequests, type PullRequest,
} from "./prCore";

const pr = (o: Partial<PullRequest>): PullRequest => ({
  id: "github:o/r#1", provider: "github", repo: "r", number: 1, title: "t", url: "https://x", author: "kim", isDraft: false,
  createdAt: 0, updatedAt: 0, sourceBranch: "feat", targetBranch: "main", reviewers: [], reviewRequested: true, recentActivity: [], ...o,
});

describe("prCore", () => {
  it("승인 상태와 정렬", () => {
    expect(approval(pr({ reviewers: [] })).kind).toBe("noReviewers");
    expect(approval(pr({ reviewers: [{ name: "a", state: "approved" }, { name: "b", state: "pending" }] }))).toEqual({ kind: "waiting", n: 1, m: 2 });
    expect(approval(pr({ reviewers: [{ name: "a", state: "changesRequested" }] })).kind).toBe("changesRequested");
    const a = pr({ id: "a", createdAt: 2 }), b = pr({ id: "b", createdAt: 1, myReviewAt: 5 }), c = pr({ id: "c", createdAt: 1 });
    expect(sortReviewRequests([a, b, c]).map((x) => x.id)).toEqual(["c", "a", "b"]);
    const ch = pr({ id: "x", reviewers: [{ name: "a", state: "changesRequested" }] });
    expect(sortMine([pr({ id: "y", updatedAt: 9 }), ch])[0].id).toBe("x");
  });

  it("id 해석과 체크아웃 명령", () => {
    expect(githubParts("github:own/repo#12")).toEqual(["own", "repo", 12]);
    expect(bitbucketParts("bitbucket:ws/slug#3")).toEqual(["ws", "slug", 3]);
    expect(githubParts("bitbucket:ws/slug#3")).toBeNull();
    expect(checkoutCommand("feature/ABC-1_x")).toBe("git fetch origin && git checkout feature/ABC-1_x");
    expect(checkoutCommand("a b")).toBe("git fetch origin && git checkout 'a b'");
  });

  it("리뷰 필터와 개수", () => {
    const list = [
      pr({ id: "github:o/a#1", repo: "a", author: "kim" }),
      pr({ id: "github:o/b#2", repo: "b", author: "lee", myReviewAt: 10, lastCommitAt: 20 }),
      pr({ id: "github:o/b#3", repo: "b", author: "lee", myReviewAt: 10, lastCommitAt: 5 }),
    ];
    expect(list.map(reviewStatus)).toEqual(["unreviewed", "newCommits", "reviewed"]);
    expect(filterReviews(list, new Set(), new Set(["github:o/b"]), new Set())).toHaveLength(2);
    const f = facets(list, "repo", new Set(), new Set(["github:o/zzz"]), new Set(["lee"]));
    expect(f.map((x) => [x.label, x.count])).toEqual([["b", 2], ["zzz", 0]]);
  });

  it("알림: 처음은 조용히, 그다음 새 요청·승인·변경 요청·댓글", () => {
    const req = pr({ id: "github:o/r#9" });
    const mine = pr({ id: "github:o/r#1", reviewers: [{ name: "a", state: "pending" }, { name: "b", state: "pending" }] });
    const s0 = mergedSnapshot(null, snapshot([], [mine], null), new Set(["github"]));
    expect(notifications(null, s0, [], [mine])).toEqual([]);
    const mine2 = { ...mine, reviewers: [{ name: "a", state: "approved" as const }, { name: "b", state: "changesRequested" as const }], recentActivity: [{ id: "c1", author: "a" }] };
    const s1 = mergedSnapshot(s0, snapshot([req], [mine2], s0), new Set(["github"]));
    const n = notifications(s0, s1, [req], [mine2]);
    expect(n.map((x) => x.kind)).toEqual(["newReviewRequest", "approved", "changesRequested", "comments"]);
    // 실패한 제공자 항목은 직전 그대로
    const s2 = mergedSnapshot(s1, snapshot([], [], s1), new Set(["bitbucket"]));
    expect(s2.reviewRequestIDs).toContain("github:o/r#9");
  });

  it("배지는 안 본 요청 + 변경 요청 받은 내 PR", () => {
    const r = [pr({ id: "a" }), pr({ id: "b" })];
    expect(badgeCount(r, [pr({ reviewers: [{ name: "x", state: "changesRequested" }] })], new Set(["a"]))).toBe(2);
    expect(markApproved(pr({}), "me", 5).reviewers).toEqual([{ name: "me", state: "approved", at: 5 }]);
  });

  it("GitHub 응답 해석", () => {
    const node = (n: number, extra = {}) => ({
      number: n, title: "T", url: `https://github.com/o/r/pull/${n}`, createdAt: "2026-11-10T00:00:00Z", updatedAt: "2026-11-11T00:00:00Z",
      repository: { nameWithOwner: "o/r", name: "r" }, author: { login: "kim" }, headRefName: "f", baseRefName: "main",
      latestOpinionatedReviews: { nodes: [{ author: { login: "me" }, state: "APPROVED", submittedAt: "2026-11-12T00:00:00Z" }] },
      reviewRequests: { nodes: [{ requestedReviewer: { login: "lee" } }] }, ...extra,
    });
    const d = decodeGitHub({ data: { viewer: { login: "me" }, requested: { nodes: [node(1)] }, reviewed: { nodes: [node(1), node(2)] }, mine: { nodes: [node(3, { recentComments: { nodes: [{ id: "c", author: { login: "lee" } }, { id: "d", author: { login: "me" } }] } })] } } }, "me");
    expect(d.reviewRequests.map((p) => [p.number, p.reviewRequested])).toEqual([[1, true], [2, false]]);
    expect(d.reviewRequests[0].reviewers.map((r) => r.name)).toEqual(["me", "lee"]);
    expect(d.reviewRequests[0].myReviewAt).toBe(Date.parse("2026-11-12T00:00:00Z"));
    expect(d.mine[0].recentActivity).toEqual([{ id: "c", author: "lee" }]);
    expect(() => decodeGitHub({ errors: [{ message: "Bad credentials" }] }, "me")).toThrow("Bad credentials");
  });

  it("Bitbucket 응답 해석", () => {
    const j = { values: [{
      id: 7, title: "BB", created_on: "2026-11-10T00:00:00.123456+00:00", destination: { repository: { full_name: "ws/slug", name: "Slug" }, branch: { name: "main" } },
      source: { branch: { name: "f" } }, author: { display_name: "Kim" }, comment_count: 2,
      participants: [{ role: "REVIEWER", user: { uuid: "{me}", display_name: "Me" }, approved: true, participated_on: "2026-11-11T00:00:00+00:00" }],
      reviewers: [{ uuid: "{me}", display_name: "Me" }, { uuid: "{x}", display_name: "X" }],
    }], next: "https://api.bitbucket.org/2.0/x?page=2" };
    const r = decodeBitbucketPRs(j, "{me}");
    expect(r.prs[0].id).toBe("bitbucket:ws/slug#7");
    expect(r.prs[0].reviewers.map((x) => [x.name, x.state])).toEqual([["Me", "approved"], ["X", "pending"]]);
    expect(r.prs[0].myReviewAt).toBe(Date.parse("2026-11-11T00:00:00Z"));
    expect(safeNext(r.next)).toBe(r.next);
    expect(safeNext("https://evil.com/x")).toBeNull();
  });

  it("Bitbucket 원격 주소와 git config", () => {
    expect(parseBitbucketRemote("git@bitbucket.org:ws/slug.git")).toEqual({ workspace: "ws", slug: "slug" });
    expect(parseBitbucketRemote("https://u@bitbucket.org/ws/slug.git")).toEqual({ workspace: "ws", slug: "slug" });
    expect(parseBitbucketRemote("ssh://git@bitbucket.org:7999/ws/slug")).toEqual({ workspace: "ws", slug: "slug" });
    expect(parseBitbucketRemote("https://notbitbucket.org/ws/slug")).toBeNull();
    expect(originFromConfig('[core]\n\turl = no\n[remote "origin"]\n\turl = git@bitbucket.org:a/b.git\n')).toBe("git@bitbucket.org:a/b.git");
  });

  it("HTTP 오류 분류", () => {
    expect(classifyHttp(429, null, "30", null, "GitHub").kind).toBe("rate");
    expect(classifyHttp(403, "0", null, null, "GitHub").kind).toBe("rate");
    expect(classifyHttp(401, null, null, null, "GitHub").kind).toBe("auth");
    expect(classifyHttp(500, null, null, null, "GitHub")).toEqual({ kind: "http", code: 500 });
  });
});
