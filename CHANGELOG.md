# HiveRoom — 개발 내역 (CHANGELOG)

> 최종 업데이트: 2026-05-13

---

## [현재] AI 전용 Edit Room + 맵 버그 수정

### Hotfix: 전체 맵 미표시 버그 수정
- **원인**: Edit Room AI 전환 작업에서 `<canvas id="room-cv">` 를 HTML에서 완전히 제거했으나, JS 최상단의 `const RCV = document.getElementById('room-cv')` 가 `null` 을 반환하여 스크립트 전체 실행 중단
- **수정**: `<canvas id="room-cv" style="display:none;">` 로 숨김 처리 — JS 참조 유지, 화면에는 미표시

---

## Edit Room — AI 전용 모드 전환

### 변경 개요
기존 하이브리드(아이템 선택 + AI 탭) 구조에서 **AI 전용** 구조로 전면 교체.  
`gemini-test.html` 의 이미지 생성 방식을 참조하여 구현.

### UI 구조 변경

| 영역 | 이전 | 이후 |
|------|------|------|
| **con-left** | room-cv 캔버스(460px) + 아이템 컨트롤(크기/레이어/플립) + AI 썸네일(88px) | AI 생성 이미지 캔버스(300px) + Generate/Regenerate 버튼 |
| **con-right** | 6개 탭(벽지/바닥/가구/장식/아이템/AI) + 아이템 그리드 | 스크롤 가능한 AI 옵션 폼 (Room Type / Mood / Wall Deco / Furniture / Custom prompt) |

### 세부 변경 사항

**HTML**
- `con-left`: `preview-area`, `item-ctrl`, `ai-gen-section` 제거 → `ai-preview-wrap` + `ai-room-canvas` + 버튼 배치
- `con-right`: 탭 + 5개 아이템 그리드 제거 → 단일 AI 선택 폼 (Room/Mood 셀렉트, Wall max 2개, Furniture max 5개, 커스텀 프롬프트 입력)
- `gemini-test.html` 에 있는 옵션 추가: Dining room, Glass panels 등

**CSS**
- `.con-left` 너비: 510px → 340px
- `#ai-room-canvas`: 88×88 → 300px 반응형 (max-width: 300px, height: auto)
- `.ai-preview-wrap`, `.ai-ctrl-row` 신규 추가
- 모바일: `max-width: min(280px, 80vw)` 적용

**JavaScript**
- `startEditRoom()`: `buildGrids()`, `refreshLabel()`, `updateProg()`, `renderRoom()` 제거. 대신 기존 room.jpg를 `ai-room-canvas` 에 미리 표시
- `applyAICanvas()`: 고정 좌표(cx=320, cy=330, r=275) → `detectHexVertices()` 동적 육각형 감지 방식으로 교체
- `registerRoom()`: RCV(room-cv)에서 크롭 → `ai-room-canvas` 에서 직접 JPEG 생성. AI 이미지 미생성 시 경고 알림
- `showDone()`: 썸네일 소스 RCV → `ai-room-canvas`

---

## AI 이미지 생성 — Job Polling 방식 전환

### 변경 개요
단일 `fetch` + 5분 대기 방식에서 **비동기 Job Queue + Polling** 방식으로 교체.  
화면 잠금 / 탭 전환 후 돌아와도 생성이 끊기지 않음.

### 추가된 상수 및 함수

| 항목 | 설명 |
|------|------|
| `PENDING_JOB_KEY` | localStorage 키 (`hiveroom_pending_job`) |
| `_pollingActive` | 중복 폴링 방지 플래그 |
| `generateAIRoom()` | POST → `job_id` 수신 → localStorage 저장 → `pollJobResult()` 호출 |
| `pollJobResult()` | 2.5초 간격 polling, 타이머/큐 감지/5분 타임아웃 포함 |
| `checkPendingJob()` | 앱 복귀 시 미완료 작업 자동 재개 |
| `visibilitychange` 리스너 | 화면 잠금 해제/탭 복귀 시 `checkPendingJob()` 호출 |

---

## Tips 팝업 개선

### 변경 사항
- **첫 방문 시 1회만 표시**: `initTips()` 에서 `localStorage.getItem('tips_seen')` 확인. 미설정 시에만 팝업 표시
- **닫기 시 localStorage 저장**: `closeTips()` 에서 `localStorage.setItem('tips_seen', '1')` 저장
- **헤더 Tips 버튼 추가**: `💡 Tips` 버튼 클릭으로 언제든 팝업 재열람 가능 (`openTips()` 함수)
- `#tips-ov` 초기 상태: `class="hidden"` 추가 (JS 실행 전 팝업 깜빡임 방지)

---

## Edit Room — `applyAICanvas` / `startEditRoom` 버그 수정

### 수정 사항
- **`applyAICanvas` 캔버스 ID 오류**: `ai-preview-cv` (존재하지 않는 엘리먼트) → `ai-room-canvas` 로 수정
- **`startEditRoom` design_json 복원 누락**: 기존 방 수정 시 저장된 벽지/바닥/가구 선택값이 초기화되는 문제 수정. design_json 파싱 후 `SEL`, `POS`, `SIZE`, `FLIP`, `LAYER_ORDER` 복원 로직 추가

---

## Room NFT 팝업 — 한국어 → 영어 번역

### 번역 항목
| 한국어 | 영어 |
|--------|------|
| 출고 | Withdraw |
| 입고 | Deposit |
| 스테이킹 | Staking |
| 방 NFT 관리 | Room NFT Management |
| 주요 기능 버튼 레이블 전반 | 영어로 전환 |

---

## AGW (Abstract Global Wallet) 연동 복원

### 배경
지갑 연결 버튼 클릭 시 브라우저 확장 지갑(MetaMask)이 실행되던 문제 수정.

### 복원 내용
- `walletBtnClick()` → `showWalletSelector()` 호출로 변경
- AGW 팝업 UI (`wallet-selector-ov`) 복원: AGW / MetaMask 선택 화면
- `connectAbstractWallet()`: ECDH 키 교환 + `https://privy.abs.xyz/cross-app/connect` 팝업 + 스마트 월렛 주소 파생
- `_tryRestoreAGWWallet()`: 페이지 로드 시 localStorage에서 AGW 연결 자동 복원
- 관련 상수: `AGW_APP_ID`, `ONCHAIN` (HIVE/TILE/MARKET/PAYMASTER 컨트랙트 주소)

---

## 기타

### `.gitignore` 추가
- `.claude/` 디렉토리를 git 추적에서 제외

### CLAUDE.md 추가
- Claude Code 작업 가이드 (토큰 효율, 편집 규칙, 개발 규칙 등) 문서화

---

## 기술 스택

- **Frontend**: Vanilla HTML / CSS / JavaScript (단일 파일 SPA — `index.html`)
- **Backend**: Supabase (PostgreSQL, Storage, Realtime)
- **AI 이미지 생성**: ERNIE-Image-Turbo via ngrok proxy (`/sdapi/v1/txt2img`)
- **온체인**: Abstract Testnet (Chain ID 11124), ERC-721 UUPS Proxy
- **지갑**: AGW (Abstract Global Wallet) via `@privy-io/cross-app-connect`
