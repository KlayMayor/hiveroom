// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title HIVEToken
 * @notice HiveRoom의 온체인 HIVE 토큰 (ERC-20, UUPS 업그레이드 가능)
 *
 * 주요 기능:
 * - claim()     : in-app HIVE → on-chain HIVE 민팅 (서버 서명 필요, 최소 5000)
 * - burnForInApp(): on-chain HIVE → in-app HIVE 소각 (이벤트 발생 → 서버가 잔액 증가)
 *
 * 발행 상한: 무제한
 * 클레임 수수료: 0%
 * 클레임 최소 수량: 5,000 HIVE
 * 클레임 쿨타임: 24시간
 */
contract HIVEToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable
{
    using ECDSA for bytes32;

    // ─── Roles ───────────────────────────────────────────────────────────
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MARKET_ROLE   = keccak256("MARKET_ROLE");

    // ─── 상수 ────────────────────────────────────────────────────────────
    uint256 public constant CLAIM_MINIMUM  = 5_000 * 10 ** 18; // 최소 클레임 수량
    uint256 public constant CLAIM_COOLDOWN = 24 hours;          // 클레임 쿨타임

    // EIP-712 타입해시
    bytes32 private constant CLAIM_TYPEHASH = keccak256(
        "Claim(address user,uint256 amount,uint256 nonce)"
    );

    // ─── 상태 변수 ────────────────────────────────────────────────────────
    address public serverSigner;                         // 서버 서명자 주소
    mapping(address => uint256) public claimNonce;       // 재사용 방지 nonce
    mapping(address => uint256) public lastClaimTime;    // 마지막 클레임 시각

    // ─── 이벤트 ──────────────────────────────────────────────────────────
    event Claimed(address indexed user, uint256 amount);
    event BurnedForInApp(address indexed user, uint256 amount);
    event ServerSignerUpdated(address indexed oldSigner, address indexed newSigner);

    // ─── 초기화 ──────────────────────────────────────────────────────────
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _serverSigner) external initializer {
        __ERC20_init("HIVE Token", "HIVE");
        __AccessControl_init();
        __EIP712_init("HIVEToken", "1");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        serverSigner = _serverSigner;
    }

    // ─── 핵심 기능 ────────────────────────────────────────────────────────

    /**
     * @notice in-app HIVE → on-chain HIVE 클레임
     * @param amount 클레임할 수량 (18 decimals)
     * @param signature 서버가 발급한 ECDSA 서명
     *
     * 서버 서명 메시지: EIP-712 구조체 Claim(user, amount, nonce)
     */
    function claim(uint256 amount, bytes calldata signature) external {
        address user = msg.sender;

        // 최소 수량 확인
        require(amount >= CLAIM_MINIMUM, "HIVEToken: below minimum claim amount");

        // 쿨타임 확인
        require(
            block.timestamp >= lastClaimTime[user] + CLAIM_COOLDOWN,
            "HIVEToken: claim cooldown active"
        );

        // 서버 서명 검증
        bytes32 structHash = keccak256(
            abi.encode(CLAIM_TYPEHASH, user, amount, claimNonce[user])
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = digest.recover(signature);
        require(recovered == serverSigner, "HIVEToken: invalid server signature");

        // 상태 업데이트
        claimNonce[user]++;
        lastClaimTime[user] = block.timestamp;

        // 민팅
        _mint(user, amount);

        emit Claimed(user, amount);
    }

    /**
     * @notice on-chain HIVE 소각 → in-app 잔액 증가 요청
     * @param amount 소각할 수량 (18 decimals)
     *
     * 이 함수 호출 후 서버가 BurnedForInApp 이벤트를 감지하여
     * Supabase in-app 잔액을 amount만큼 증가시킨다.
     */
    function burnForInApp(uint256 amount) external {
        require(amount > 0, "HIVEToken: amount must be > 0");
        _burn(msg.sender, amount);
        emit BurnedForInApp(msg.sender, amount);
    }

    // ─── 관리자 기능 ──────────────────────────────────────────────────────

    /// @notice 서버 서명자 주소 변경 (DEFAULT_ADMIN_ROLE)
    function setServerSigner(address _newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newSigner != address(0), "HIVEToken: zero address");
        emit ServerSignerUpdated(serverSigner, _newSigner);
        serverSigner = _newSigner;
    }

    /// @notice 특정 유저 nonce 조회 (프론트엔드용)
    function getClaimNonce(address user) external view returns (uint256) {
        return claimNonce[user];
    }

    /// @notice 다음 클레임 가능 시각 조회
    function nextClaimTime(address user) external view returns (uint256) {
        return lastClaimTime[user] + CLAIM_COOLDOWN;
    }

    // ─── UUPS 업그레이드 가드 ─────────────────────────────────────────────
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}
