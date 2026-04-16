// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./HIVEToken.sol";
import "./HiveRoomTile.sol";

/**
 * @title HiveRoomMarket
 * @notice HiveRoom 타일 거래 컨트랙트 (UUPS 업그레이드 가능)
 *
 * 핵심 기능: buyTile()
 * - HIVE 이전 (buyer → seller) 과 NFT 강제 이전 (seller → buyer) 을 하나의 트랜잭션으로 처리
 * - 서버 서명으로 가격 변조 방지
 * - NFT가 없는 타일도 구매 가능 (Supabase DB 소유권만 이전, 서버 이벤트로 처리)
 */
contract HiveRoomMarket is
    Initializable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable
{
    // ─── 재진입 방지 (inline) ─────────────────────────────────────────────
    uint256 private _reentrancyStatus; // 1 = 미진입, 2 = 진입중

    modifier nonReentrant() {
        require(_reentrancyStatus != 2, "HiveRoomMarket: reentrant call");
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }
    using ECDSA for bytes32;

    // ─── Roles ───────────────────────────────────────────────────────────
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // EIP-712 타입해시
    bytes32 private constant BUY_TYPEHASH = keccak256(
        "Buy(address buyer,uint256 tileNumber,address seller,uint256 price,uint256 nonce)"
    );

    // ─── 상태 변수 ────────────────────────────────────────────────────────
    HIVEToken     public hive;           // HIVEToken 컨트랙트
    HiveRoomTile  public tile;           // HiveRoomTile 컨트랙트
    address       public serverSigner;   // 서버 서명자 주소

    mapping(address => uint256) public buyNonce; // 재사용 방지 nonce

    // ─── 이벤트 ──────────────────────────────────────────────────────────
    event TilePurchased(
        uint256 indexed tileNumber,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        bool nftTransferred  // NFT 강제 이전 여부
    );
    event ServerSignerUpdated(address indexed oldSigner, address indexed newSigner);

    // ─── 초기화 ──────────────────────────────────────────────────────────
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _hive,
        address _tile,
        address _serverSigner
    ) external initializer {
        __AccessControl_init();
        __EIP712_init("HiveRoomMarket", "1");
        _reentrancyStatus = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        hive         = HIVEToken(_hive);
        tile         = HiveRoomTile(_tile);
        serverSigner = _serverSigner;
    }

    // ─── 핵심 기능 ────────────────────────────────────────────────────────

    /**
     * @notice 타일 구매
     * @param tileNumber 구매할 타일 번호
     * @param seller     현재 타일 소유자 주소
     * @param price      거래 가격 (HIVE, 18 decimals)
     * @param signature  서버가 발급한 ECDSA 서명 (가격 변조 방지)
     *
     * 처리 순서:
     * 1. 서버 서명 검증 (buyer, tileNumber, seller, price, nonce 포함)
     * 2. HIVE: buyer → seller 이전 (ERC-20 transferFrom, 사전 approve 필요)
     * 3. NFT 강제 이전: tile.minted() 확인 후 forceTransfer 호출
     * 4. TilePurchased 이벤트 발생 → 서버가 Supabase 동기화
     */
    function buyTile(
        uint256 tileNumber,
        address seller,
        uint256 price,
        bytes calldata signature
    ) external nonReentrant {
        address buyer = msg.sender;

        require(buyer != seller, "HiveRoomMarket: cannot buy own tile");
        require(price > 0, "HiveRoomMarket: price must be > 0");

        // 서버 서명 검증
        bytes32 structHash = keccak256(
            abi.encode(BUY_TYPEHASH, buyer, tileNumber, seller, price, buyNonce[buyer])
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = digest.recover(signature);
        require(recovered == serverSigner, "HiveRoomMarket: invalid server signature");

        // nonce 증가 (재사용 방지)
        buyNonce[buyer]++;

        // HIVE 이전: buyer → seller
        // buyer가 사전에 Market 컨트랙트에 approve 해야 함
        require(
            hive.transferFrom(buyer, seller, price),
            "HiveRoomMarket: HIVE transfer failed"
        );

        // NFT 강제 이전 (NFT가 민팅된 경우만)
        bool nftTransferred = false;
        if (tile.minted(tileNumber)) {
            address nftOwner = tile.ownerOf(tileNumber);
            // NFT 소유자가 seller와 일치하는 경우만 강제 이전
            if (nftOwner == seller) {
                tile.forceTransfer(seller, buyer, tileNumber);
                nftTransferred = true;
            }
        }

        emit TilePurchased(tileNumber, seller, buyer, price, nftTransferred);
    }

    /**
     * @notice HIVE approve + buyTile 원자적 실행 (UX 개선용)
     * @dev buyer가 별도로 approve를 호출하지 않아도 되도록
     *      Paymaster 환경에서 활용 가능
     */
    function approveAndBuy(
        uint256 tileNumber,
        address seller,
        uint256 price,
        bytes calldata signature
    ) external nonReentrant {
        address buyer = msg.sender;

        // HIVE approve (buyer가 직접 approve 대신 이 함수 내에서 처리)
        // 주의: 이 방식은 buyer가 직접 호출해야 함
        hive.transferFrom(buyer, address(this), price);

        // seller에게 전달
        require(
            hive.transfer(seller, price),
            "HiveRoomMarket: HIVE transfer to seller failed"
        );

        // 서버 서명 검증
        bytes32 structHash = keccak256(
            abi.encode(BUY_TYPEHASH, buyer, tileNumber, seller, price, buyNonce[buyer])
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = digest.recover(signature);
        require(recovered == serverSigner, "HiveRoomMarket: invalid server signature");

        buyNonce[buyer]++;

        bool nftTransferred = false;
        if (tile.minted(tileNumber)) {
            address nftOwner = tile.ownerOf(tileNumber);
            if (nftOwner == seller) {
                tile.forceTransfer(seller, buyer, tileNumber);
                nftTransferred = true;
            }
        }

        emit TilePurchased(tileNumber, seller, buyer, price, nftTransferred);
    }

    // ─── 관리자 기능 ──────────────────────────────────────────────────────

    function setServerSigner(address _newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newSigner != address(0), "HiveRoomMarket: zero address");
        emit ServerSignerUpdated(serverSigner, _newSigner);
        serverSigner = _newSigner;
    }

    function getBuyNonce(address user) external view returns (uint256) {
        return buyNonce[user];
    }

    // ─── UUPS 업그레이드 가드 ─────────────────────────────────────────────
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}
