# HiveRoom On-Chain Architecture Design
> Chain: Abstract Testnet (ZKsync ZK Stack L2) — Chain ID: 11124
> Last updated: 2026-05-13

---

## 1. 전체 구조 Overview

```
┌─────────────────────────────────────────────────────┐
│                   HiveRoom Frontend                  │
│  (index.html — vanilla JS + ethers.js / AGW)        │
└────────────┬──────────────────────┬─────────────────┘
             │                      │
     온체인 읽기/쓰기           오프체인 데이터
             │                      │
┌────────────▼────────────┐  ┌──────▼──────────────────┐
│  Abstract Testnet L2    │  │   Supabase (유지)        │
│  (EraVM / ZKsync Stack) │  │  - 방 이미지 (room.jpg) │
│                         │  │  - twitterId / email    │
│  HIVEToken.sol (ERC-20) │  │  - in-app HIVE 잔액     │
│  HiveRoomTile.sol (721) │  │  - design_json 꾸미기   │
│  HiveRoomMarket.sol     │  │  - Realtime 동기화      │
│  HiveRoomPaymaster.sol  │  └─────────────────────────┘
└─────────────────────────┘
```

### 역할 분리 원칙

| 데이터 | 저장 위치 | 이유 |
|--------|-----------|------|
| 타일 소유권 | 온체인 (NFT) | 진짜 소유권 증명 |
| HIVE 잔액 (in-app) | Supabase | 빠른 읽기/쓰기, 무료 |
| HIVE 잔액 (on-chain) | 온체인 (ERC-20) | 외부 거래 가능 |
| 방 이미지 | Supabase Storage (`room-pic/`) | AI 생성 JPEG 저장 |
| 방 꾸미기 데이터 | Supabase (`design_json`) | 아이템 좌표/레이어 |
| 타일 메타데이터 | IPFS + 온체인 tokenURI | NFT 표준 준수 |

---

## 2. 배포된 컨트랙트 주소 (Abstract Testnet)

| 컨트랙트 | 주소 | 상태 |
|----------|------|------|
| HIVEToken (ERC-20) | `0xE46AfBa60F86D34F110d5ADC5Ea763dB883096dE` | ✅ 배포됨 |
| HiveRoomTile (ERC-721 UUPS) | `0xe02F5144303956dAe6eB42836D9Fc26A0Ca3277a` | ✅ 배포됨 |
| HiveRoomMarket | `0x49386B0d73Ac64BfD302ADd525712E2c5C0801A4` | ✅ 배포됨 |
| HiveRoomPaymaster | `0x8BCa39d4413AacaF5aE1FCEF499a7dB7045b22cB` | ✅ 배포됨 |

```javascript
// index.html 내 상수
const ONCHAIN = {
  HIVE:      '0xE46AfBa60F86D34F110d5ADC5Ea763dB883096dE',
  TILE:      '0xe02F5144303956dAe6eB42836D9Fc26A0Ca3277a',
  MARKET:    '0x49386B0d73Ac64BfD302ADd525712E2c5C0801A4',
  PAYMASTER: '0x8BCa39d4413AacaF5aE1FCEF499a7dB7045b22cB',
};
const PAYMASTER_INPUT = '0x8c5a3445...'; // GeneralPaymasterInput encoded
```

---

## 3. 스마트 컨트랙트 설계

### 3-1. HIVEToken.sol (ERC-20)

```solidity
contract HIVEToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // 클레임: in-app HIVE → on-chain HIVE 민팅
    // 서버 서명 검증 후 mint
    function claim(uint256 amount, bytes calldata serverSignature) external;

    // getClaimNonce: 리플레이 방지용 nonce
    function getClaimNonce(address user) external view returns (uint256);

    // nextClaimTime: 24h 쿨타임 확인
    function nextClaimTime(address user) external view returns (uint256);

    // 소각: on-chain HIVE → in-app HIVE 환원
    function burnForInApp(uint256 amount) external;
}
```

**ABI (index.html 참조)**
```javascript
const HIVE_ABI = [
  'function claim(uint256 amount, bytes calldata signature) external',
  'function burnForInApp(uint256 amount) external',
  'function getClaimNonce(address user) external view returns (uint256)',
  'function nextClaimTime(address user) external view returns (uint256)',
  'function balanceOf(address account) external view returns (uint256)',
];
```

**클레임 흐름 (in-app → on-chain)**
```
1. 유저가 헤더 HIVE 잔액 클릭 → openClaimModal()
2. 최소 5,000 HIVE 이상 확인
3. 프론트 → 서버에 클레임 서명 요청
4. 서버가 Supabase 잔액 확인 + ECDSA 서명 발급
5. claim(amount, signature) 트랜잭션 전송 (Paymaster 무가스)
6. 컨트랙트 서명 검증 → HIVE 민팅
7. 서버가 Supabase in-app 잔액 차감
```

**소각 흐름 (on-chain → in-app)**
```
1. burnForInApp(amount) 트랜잭션 전송
2. 컨트랙트 burn 이벤트 발생
3. 서버(Edge Function)가 이벤트 감지
4. Supabase in-app 잔액 += amount
```

---

### 3-2. HiveRoomTile.sol (ERC-721 UUPS Proxy)

```solidity
contract HiveRoomTile is ERC721Upgradeable, AccessControlUpgradeable {
    bytes32 public constant MARKET_ROLE = keccak256("MARKET_ROLE");

    // tokenId = 타일 번호 (1:1 매핑)
    mapping(uint256 => bool) public minted;

    // 민팅: 서버 서명으로 소유권 검증
    function mint(uint256 tileNumber, bytes calldata serverSignature) external;

    // 강제 이전: MARKET_ROLE만 호출 가능
    function forceTransfer(address from, address to, uint256 tokenId)
        external onlyRole(MARKET_ROLE);

    // tokenURI: IPFS 메타데이터
    function tokenURI(uint256 tokenId) public view returns (string memory);
}
```

**NFT 민팅 흐름**
```
1. 유저가 내 방 정보 패널 열람
2. minted[tileNumber] 온체인 확인
3. NFT 없음 → "🖼 Mint NFT" 버튼 표시
4. 버튼 클릭 → 서버에 민팅 서명 요청
5. 서버가 Supabase ownerEmail 확인 → 서명 발급
6. mint(tileNumber, signature) 전송 (Paymaster 무가스)
7. NFT 발행 → 버튼 "🔗 View NFT" 로 전환
```

**타일 강제 이전 (구매 시)**
```
[타일에 NFT 없음]            [타일에 NFT 있음]
Supabase DB 소유권 이전만    Supabase DB 이전 +
                      →      forceTransfer(seller → buyer)
                             (Market 컨트랙트가 자동 처리)
```

---

### 3-3. HiveRoomMarket.sol

```solidity
contract HiveRoomMarket {
    HIVEToken public hive;
    HiveRoomTile public tile;

    function buyTile(
        uint256 tileNumber,
        address seller,
        uint256 price,
        bytes calldata serverSignature
    ) external {
        // 1. 서버 서명 검증 (가격 변조 방지)
        // 2. HIVE: buyer → seller 이전
        hive.transferFrom(msg.sender, seller, price);
        // 3. NFT 강제 이전 (있는 경우만)
        if (tile.minted(tileNumber)) {
            tile.forceTransfer(seller, msg.sender, tileNumber);
        }
        emit TilePurchased(tileNumber, seller, msg.sender, price);
    }
}
```

---

### 3-4. HiveRoomPaymaster.sol

```solidity
contract HiveRoomPaymaster is IPaymaster {
    // HiveRoom 컨트랙트 호출에 한해 가스비 전액 대납
    // 유저 가스비 = 0
    function validateAndPayForPaymasterTransaction(...) external;
}
```

**운영 메모**
- 예산: $100 (Abstract 가스비 ~$0.001/tx → 약 100,000 트랜잭션 대납)
- 잔액 $20 이하 시 모니터링 알림 권장
- 재충전: ETH → Abstract 브릿지 → Paymaster deposit

---

## 4. AGW (Abstract Global Wallet) 연동

### 개요
Privy 기반 크로스앱 지갑. 이메일 로그인 후 AGW로 스마트 월렛 자동 생성/연결.

### 구현 방식
```
ECDH 키 교환 → 팝업(https://privy.abs.xyz/cross-app/connect) → 스마트 월렛 주소 파생
```

### 상수
```javascript
const AGW_APP_ID = 'cm04asygd041fmry9zmcyn5o5';
// Chain: Abstract Testnet, ID: 11124
```

### localStorage 저장 키
| 키 | 내용 |
|----|------|
| `agw_addr` | 스마트 월렛 주소 |
| `agw_shared` | ECDH 공유 시크릿 (hex) |
| `agw_pub` | AGW 공개키 (hex) |
| `agw_transact_url` | 트랜잭션 요청 URL |

### 주요 함수
| 함수 | 설명 |
|------|------|
| `connectAbstractWallet()` | ECDH 키 교환 + 팝업 오픈 + 스마트 월렛 주소 파생 |
| `_agwRequest(method, params)` | 암호화된 크로스앱 트랜잭션 요청 |
| `_tryRestoreAGWWallet()` | 페이지 로드 시 localStorage에서 AGW 연결 복원 |
| `walletBtnClick()` | AGW / MetaMask 선택 오버레이 표시 |
| `disconnectWallet()` | localStorage AGW 키 전체 삭제 |

### EIP-712 서명 (민팅 권한)
```javascript
// HiveRoomTile 민팅 시 서버 서명 검증
const domain = {
  name: 'HiveRoomTile',
  version: '1',
  chainId: 11124,
  verifyingContract: ONCHAIN.TILE,
};
```

---

## 5. HIVE 토큰 경제

### 5-1. In-app vs On-chain 이중 구조

```
[In-app HIVE]  ←── Supabase ──→  빠른 게임 내 거래
     ↕  Claim (최소 5,000 HIVE)
     ↕  Burn  (제한 없음)
[On-chain HIVE] ←── Abstract ──→  외부 거래 / 보관 가능
```

### 5-2. HIVE 획득 방법

| 방법 | 수량 | 주기 |
|------|------|------|
| 최초 로그인 보상 | 300 HIVE | 1회 |
| 일일 자동 지급 | 10 HIVE | 매일 UTC 00:00 |
| 출석체크 퀴즈 | 5 HIVE | 1회/일 |
| 타일 투자 수익 | 타일 가치 × 수익률 | 월별 |

### 5-3. 클레임 규칙

| 항목 | 값 |
|------|----||
| 최소 클레임 수량 | 5,000 HIVE |
| 클레임 쿨타임 | 24시간 |
| 클레임 수수료 | 0% (1:1 차감) |
| 지갑 연결 필요 | AGW |

### 5-4. 어뷰징 방지 장치

```
① 최소 클레임 5,000 HIVE → 신규 계정(300 HIVE) 즉시 클레임 불가
② 클레임 서명은 서버가 발급 → 유저 직접 호출 불가
③ 온체인 nonce (getClaimNonce) → 리플레이 공격 방지
④ 24h 쿨타임 (nextClaimTime) → 반복 클레임 방지
⑤ Supabase에 클레임 이력 기록
```

---

## 6. 프론트엔드 온체인 연동

### 6-1. 지갑 선택 UI

```
walletBtnClick()
  ↓
wallet-selector-ov 오버레이
  ├── ⬡ Abstract Global Wallet  →  connectAbstractWallet()
  └── 🦊 MetaMask / Browser     →  connectMetaMask()
```

### 6-2. 헤더 HIVE 잔액 → Claim 모달

```
🍯 1,250 HIVE  (클릭 가능)
      ↓ openClaimModal()
┌───────────────────────────┐
│  💰 HIVE 클레임 / 소각    │
│  In-app 잔액: 1,250 HIVE  │
│  On-chain 잔액: 0 HIVE    │
│  [클레임] 최소 5,000      │
│  [소각] 온체인→인앱       │
└───────────────────────────┘
```

### 6-3. 방 정보 패널 — NFT 버튼

```
내 방 패널:
  minted[tileNumber] = false → [🖼 Mint NFT]
  minted[tileNumber] = true  → [🔗 View NFT]
```

### 6-4. Room NFT 관리 팝업 (영문 UI)

| 기능 | 설명 |
|------|------|
| Stake | NFT를 컨트랙트에 스테이킹 |
| Unstake | 스테이킹 해제 |
| Withdraw | NFT 출금 |
| Deposit | NFT 입금 |

---

## 7. AI 이미지 생성 (Edit Room)

Edit Room은 AI 전용으로 운영. 생성된 이미지가 방의 `room.jpg` 로 Supabase에 저장됨.

### 흐름
```
1. Edit Room 진입 → startEditRoom()
2. 기존 room.jpg → ai-room-canvas 미리보기
3. Room/Mood/Wall/Furniture 옵션 선택
4. ✨ Generate 클릭 → generateAIRoom()
5. POST /sdapi/v1/txt2img → job_id 수신
6. pollJobResult() → 2.5초 간격 polling
7. 완료 → applyAICanvas() → 육각형 클립 적용
8. Finish → registerRoom() → ai-room-canvas → JPEG → Supabase 업로드
```

### AI 서버
- **프록시**: `https://oval-trombone-obedience.ngrok-free.dev`
- **모델**: ERNIE-Image-Turbo (Stable Diffusion WebUI API 호환)
- **서버 코드**: `ernie-server/server.py`, `ernie-server/proxy.py`

---

## 8. Supabase 구조

### DB 테이블
| 테이블 | 주요 컬럼 |
|--------|-----------|
| `rooms` | `room_number`, `email`, `twitter_id`, `occupied`, `design_json`, `interest`, `avatar_url` |
| `user_balances` | `user_email`, `balance` |
| `room_balances` | `room_number`, `balance` |

### Storage 버킷
| 버킷 | 내용 |
|------|------|
| `room-pic/{room_number}/room.jpg` | AI 생성 방 이미지 |
| `asset/` | 아이템 썸네일 (벽지/바닥/가구 등) |

### Edge Functions (`supabase/functions/`)
| 함수 | 역할 |
|------|------|
| `claim-signature` | HIVE 클레임용 ECDSA 서명 발급 |
| `mint-signature` | NFT 민팅용 서명 발급 |
| `watch-burn-events` | on-chain burn 이벤트 → Supabase 잔액 증가 |
| `watch-purchase-events` | on-chain 구매 이벤트 → Supabase 소유권 동기화 |

---

## 9. 배포 단계

### Phase 1 — 테스트넷 (✅ 완료)
- [x] HIVEToken.sol 배포
- [x] HiveRoomTile.sol 배포 (UUPS Proxy)
- [x] HiveRoomMarket.sol 배포
- [x] HiveRoomPaymaster.sol 배포
- [x] AGW 지갑 연동 (프론트엔드)
- [x] HIVE Claim / Burn UI
- [x] NFT 민팅 / View UI
- [x] Room NFT 스테이킹 UI (Stake/Unstake/Withdraw/Deposit)

### Phase 2 — 메인넷 배포 (예정)
- [ ] Paymaster 예산 확보 및 배포
- [ ] 메인넷 컨트랙트 배포
- [ ] Etherscan Verify
- [ ] 기존 유저 HIVE 스냅샷 공지

### Phase 3 — 마이그레이션 (선택)
- [ ] 기존 타일 소유자 NFT 무료 민팅 기간 제공
- [ ] 타일 구매 = 자동 NFT 이전 방식 전환

---

## 10. 확정 사항

| 항목 | 결정 | 비고 |
|------|------|------|
| HIVE 총 발행 상한선 | 무제한 | 서버 서명 + 클레임 최소값으로 남용 방지 |
| 클레임 수수료 | 0% | in-app 차감 = on-chain 민팅 수량 1:1 |
| Paymaster 예산 | $100 | ~100,000 tx 대납 가능 |
| 기존 유저 마이그레이션 | 수동 클레임 | 지갑 연결 후 본인이 직접 클레임 |
| Twitter ID 없는 유저 클레임 | 허용 | 지갑 주소 + 24h 쿨타임으로만 제한 |
