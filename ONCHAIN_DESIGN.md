# HiveRoom On-Chain Architecture Design
> Chain: Abstract (ZKsync ZK Stack L2)
> Last updated: 2026-04-16

---

## 1. 전체 구조 Overview

```
┌─────────────────────────────────────────────────────┐
│                   HiveRoom Frontend                  │
│  (index.html — vanilla JS + ethers.js / AGW SDK)    │
└────────────┬──────────────────────┬─────────────────┘
             │                      │
     온체인 읽기/쓰기           오프체인 데이터
             │                      │
┌────────────▼────────────┐  ┌──────▼──────────────────┐
│   Abstract L2 (EraVM)   │  │   Supabase (유지)        │
│                         │  │  - 방 이미지 / 꾸미기    │
│  HIVEToken.sol (ERC-20) │  │  - twitterId            │
│  HiveRoomTile.sol (721) │  │  - in-app HIVE 잔액     │
│  HiveRoomMarket.sol     │  │  - Realtime 동기화       │
└─────────────────────────┘  └─────────────────────────┘
```

### 역할 분리 원칙

| 데이터 | 저장 위치 | 이유 |
|--------|-----------|------|
| 타일 소유권 | 온체인 (NFT) | 진짜 소유권 증명 |
| HIVE 잔액 (in-app) | Supabase | 빠른 읽기/쓰기, 무료 |
| HIVE 잔액 (on-chain) | 온체인 (ERC-20) | 외부 거래 가능 |
| 방 이미지 / 꾸미기 | Supabase Storage | 대용량 파일 저장 |
| 타일 메타데이터 | IPFS + 온체인 tokenURI | NFT 표준 준수 |

---

## 2. 스마트 컨트랙트 설계

### 2-1. HIVEToken.sol (ERC-20)

```solidity
contract HIVEToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    uint256 public constant CLAIM_MINIMUM = 5000 * 10**18; // 최소 클레임 수량

    // 클레임: in-app HIVE → on-chain HIVE 민팅
    // 서버 서명 검증 후 mint
    function claim(uint256 amount, bytes calldata serverSignature) external;

    // 소각: on-chain HIVE → in-app HIVE 환원
    // burn 후 서버가 Supabase 잔액 증가
    function burnForInApp(uint256 amount) external;

    // Market 컨트랙트만 호출 가능 (타일 거래 시 HIVE 이전)
    function transferFrom(...) — 표준 ERC-20
}
```

**클레임 흐름 (in-app → on-chain)**
```
1. 유저가 헤더 HIVE 잔액 클릭
2. Claim 모달 오픈 (최소 5000 HIVE 확인)
3. 프론트 → 서버에 클레임 요청
4. 서버가 Supabase 잔액 확인 (5000 이상인지)
5. 서버가 서명(signature) 발급
6. 유저가 claim(amount, signature) 트랜잭션 전송
7. 컨트랙트가 서명 검증 → HIVE 민팅
8. 서버가 Supabase in-app 잔액 차감
```

**소각 흐름 (on-chain → in-app)**
```
1. 유저가 Claim 모달에서 "소각하기" 선택
2. burnForInApp(amount) 트랜잭션 전송
3. 컨트랙트가 burn 이벤트 발생
4. 서버(Supabase Edge Function)가 burn 이벤트 수신
5. Supabase in-app 잔액 += amount
```

---

### 2-2. HiveRoomTile.sol (ERC-721)

```solidity
contract HiveRoomTile is ERC721, AccessControl {
    bytes32 public constant MARKET_ROLE = keccak256("MARKET_ROLE");

    // tokenId = 타일 번호 (1:1 매핑)
    mapping(uint256 => bool) public minted;

    // 민팅: 방 소유자만 호출 가능
    // 서버 서명으로 소유권 검증
    function mint(uint256 tileNumber, bytes calldata serverSignature) external;

    // 강제 이전: MARKET_ROLE만 호출 가능
    // 타일 구매 시 Market 컨트랙트가 호출
    function forceTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external onlyRole(MARKET_ROLE) {
        _transfer(from, to, tokenId); // 승인 없이 강제 이전
    }

    // tokenURI: IPFS 메타데이터 (타일 번호, 좌표, ZONE 정보)
    function tokenURI(uint256 tokenId) public view returns (string memory);
}
```

**NFT 민팅 흐름**
```
1. 유저가 빈 타일 구매 → 방 꾸미기 → 맵에 등록
2. 방 정보 패널 로드 시 onchain에서 minted[tileNumber] 확인
3. NFT 없음 → "🖼 NFT 민팅하기" 버튼 표시
4. 버튼 클릭 → 서버에 민팅 권한 서명 요청
5. 서버가 Supabase에서 ownerEmail 확인
6. 서명 발급 → mint(tileNumber, signature) 전송
7. NFT 발행 완료 → 버튼 숨김
```

**강제 이전 (타일 구매 시)**
```
[타일에 NFT 없음]                [타일에 NFT 있음]
Supabase DB 소유권 이전만        Supabase DB 이전 +
                          →      forceTransfer(A → B) 호출
                                 (Market 컨트랙트가 자동 처리)
```

---

### 2-3. HiveRoomMarket.sol

```solidity
contract HiveRoomMarket {
    HIVEToken public hive;
    HiveRoomTile public tile;

    // 타일 구매 (HIVE 이전 + NFT 강제 이전)
    function buyTile(
        uint256 tileNumber,
        address seller,
        uint256 price,
        bytes calldata serverSignature
    ) external {
        // 1. 서버 서명 검증 (가격 변조 방지)
        // 2. HIVE: buyer → seller 이전
        hive.transferFrom(msg.sender, seller, price);
        // 3. NFT 강제 이전 (NFT 있는 경우만)
        if (tile.minted(tileNumber)) {
            tile.forceTransfer(seller, msg.sender, tileNumber);
        }
        // 4. 이벤트 발생 → 서버가 Supabase 동기화
        emit TilePurchased(tileNumber, seller, msg.sender, price);
    }
}
```

---

## 3. HIVE 토큰 경제 설계

### 3-1. In-app vs On-chain 이중 구조

```
[In-app HIVE]  ←─── Supabase ───→  빠른 게임 내 거래
     ↕  Claim (최소 5000)
     ↕  Burn  (제한 없음)
[On-chain HIVE] ←── Abstract ───→  외부 거래 / 보관 가능
```

### 3-2. 클레임 규칙

| 항목 | 값 |
|------|----|
| 최소 클레임 수량 | 5,000 HIVE |
| 클레임 쿨타임 | 24시간 (다중 계정 어뷰징 방지) |
| 클레임 수수료 | 5% burn (인플레이션 억제) |
| 지갑 연결 필요 | AGW (이메일 로그인 시 자동 생성) |

### 3-3. 어뷰징 방지 장치

```
① 최소 클레임 5000 HIVE → 신규 계정(300 HIVE)은 즉시 클레임 불가
② 클레임 서명은 서버(백엔드)가 발급 → 유저 직접 호출 불가
③ Twitter ID 보유 계정만 클레임 가능 (선택 적용)
④ 클레임 이력을 Supabase에 기록 → 서버 측 중복 방지
⑤ 지갑 주소 1개당 하루 1회 클레임
```

---

## 4. 프론트엔드 변경 사항

### 4-1. 추가 라이브러리

```html
<!-- ethers.js (컨트랙트 호출) -->
<script src="https://cdn.jsdelivr.net/npm/ethers@6/dist/ethers.umd.min.js"></script>

<!-- Abstract AGW SDK (지갑 연결) -->
<script src="https://cdn.jsdelivr.net/npm/@abstract-foundation/agw-client/dist/index.umd.js"></script>
```

### 4-2. 헤더 HIVE 잔액 → Claim 모달

```
기존: 🍯 1,250 HIVE  (텍스트만)
변경: 🍯 1,250 HIVE  (클릭 가능)
                ↓ 클릭
     ┌─────────────────────────┐
     │  💰 HIVE 클레임 / 소각  │
     │                         │
     │  In-app 잔액: 1,250 HIVE│
     │  On-chain 잔액: 0 HIVE  │
     │                         │
     │  [클레임] 최소 5,000    │
     │  ─────────────────────  │
     │  [소각] 온체인→인앱     │
     └─────────────────────────┘
```

### 4-3. 방 정보 패널 — NFT 민팅 버튼

```
기존 버튼: [Buy] [Invest] [Move]
추가 버튼: [🖼 Mint NFT]  ← NFT 없는 내 방에만 표시
           [🔗 View NFT]  ← NFT 있는 경우
```

### 4-4. 지갑 연결 (AGW)

```
기존: Google OAuth → 이메일 기반 로그인
변경: Google OAuth 유지 + AGW 지갑 자동 연결
     (최초 클레임 시 지갑 생성 요청)
```

---

## 5. 서버 사이드 변경 (Supabase Edge Functions)

### 추가 Edge Functions

```
POST /claim-signature
  - Supabase 잔액 >= 5000 확인
  - 클레임 쿨타임 확인
  - ECDSA 서명 발급

POST /mint-signature
  - 방 소유자 확인
  - 민팅 권한 서명 발급

GET  /watch-burn-events  (cron / Realtime)
  - 온체인 burn 이벤트 감지
  - Supabase 잔액 += burned amount

GET  /watch-purchase-events  (cron / Realtime)
  - 온체인 TilePurchased 이벤트 감지
  - Supabase ownerEmail 동기화
```

---

## 6. 배포 계획

### Phase 1 — 컨트랙트 개발 & 테스트넷
```
① HIVEToken.sol 작성 + Abstract Sepolia 배포
② HiveRoomTile.sol 작성 + 배포
③ HiveRoomMarket.sol 작성 + 배포
④ 프론트엔드 AGW 연결 + Claim UI 구현
⑤ Burn 이벤트 리스너 구현
⑥ 테스트넷에서 전체 시나리오 테스트
```

### Phase 2 — 메인넷 배포
```
① Paymaster 컨트랙트 배포 (무가스 UX)
② 메인넷 배포 (사용자 프라이빗 키 필요)
③ 컨트랙트 Verify (Etherscan)
④ 기존 유저 HIVE 잔액 스냅샷 공지
```

### Phase 3 — 마이그레이션 (선택)
```
① 기존 타일 소유자에게 NFT 무료 민팅 기간 제공
② 일정 기간 후 타일 구매 = 자동 NFT 이전 방식으로 전환
```

---

## 7. Abstract 특화 기능 활용

### Paymaster (무가스 UX)
```solidity
// 유저 가스비 0원 — 플랫폼이 전액 대납
// 타일 구매, HIVE 클레임, NFT 민팅 모두 무료
contract HiveRoomPaymaster is IPaymaster {
    function validateAndPayForPaymasterTransaction(...) {
        // HiveRoom 컨트랙트 호출에 한해 가스비 대납
    }
}
```

### Session Key
```
유저가 "HiveRoom 세션 시작" 1회 승인
→ 이후 타일 구매 / NFT 민팅 시 지갑 팝업 없음
→ 게임 UX 유지
```

---

## 8. 컨트랙트 주소 관리 (배포 후 기록)

| 컨트랙트 | Testnet (Sepolia) | Mainnet |
|----------|-------------------|---------|
| HIVEToken | TBD | TBD |
| HiveRoomTile | TBD | TBD |
| HiveRoomMarket | TBD | TBD |
| Paymaster | TBD | TBD |

---

## 9. 확정 사항 ✅

| 항목 | 결정 | 비고 |
|------|------|------|
| HIVE 총 발행 상한선 | **무제한** | 클레임 최소 5000 + 서버 서명으로 남용 방지 |
| 클레임 수수료 | **0%** | 클레임 수량 = 차감 수량 1:1 |
| Paymaster 예산 | **$100** | 소진 시 재충전 또는 일시 유가스 전환 |
| 기존 유저 마이그레이션 | **에어드랍** | 스냅샷 기준 in-app 잔액 → 온체인 자동 지급 |
| Twitter ID 없는 유저 클레임 | **허용** | 지갑 주소 + 24h 쿨타임으로만 제한 |

### Paymaster $100 운영 메모
- Abstract 가스비 ~$0.001/tx 기준 약 **100,000 트랜잭션** 대납 가능
- 소진 감지용 모니터링 알림 설정 권장 (잔액 $20 이하 시 알림)
- 재충전: ETH → Abstract 브릿지 → Paymaster 컨트랙트에 deposit

### 에어드랍 마이그레이션 계획
```
1. 온체인 배포 완료 시점에 Supabase in-app 잔액 스냅샷
2. 스냅샷 기준으로 각 유저의 지갑 주소 수집
   (최초 접속 시 AGW 지갑 연결 유도)
3. 지갑 연결한 유저에게 스냅샷 잔액만큼 HIVE 에어드랍
4. 에어드랍된 수량은 Supabase in-app 잔액에서 차감
5. 미연결 유저는 지갑 연결 후 수동 클레임 가능 (6개월 유예)
```
