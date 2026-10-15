# Bitbucket API 토큰 만들기

ATM 의 PR 탭이 Bitbucket 에서 내 리뷰 요청과 내가 올린 PR 을 읽어 오는 데 쓰는 토큰이에요. **읽기 권한만** 줍니다.

1. <https://id.atlassian.com/manage-profile/security/api-tokens> 를 연다.
2. **범위가 있는 API 토큰 만들기** 를 누른다.
3. 이름은 `ATM`, 만료일은 원하는 기간으로 정한다.
4. 앱으로 **Bitbucket** 을 고른다.
5. 권한(스코프)은 읽기 4개만 고른다.
   - `read:repository:bitbucket`
   - `read:pullrequest:bitbucket`
   - `read:user:bitbucket`
   - `read:workspace:bitbucket`
6. 만들어진 토큰을 복사한다 (이 화면을 닫으면 다시 볼 수 없다).
7. ATM 설정 > PR 의 Bitbucket 에서 Atlassian 계정 이메일과 토큰을 붙여넣고 **연결 확인** 을 누른다.

- 토큰은 ATM 설정 > 창·일반 > 비밀 정보 저장 에서 고른 곳(키체인 또는 파일)에만 저장돼요.
- 읽기 권한만 있어서 ATM 이 PR 을 바꾸거나 머지하지는 못해요.
- 만료되면 연결 확인이 실패해요. 같은 방법으로 새 토큰을 만들어 다시 붙여넣으세요.
