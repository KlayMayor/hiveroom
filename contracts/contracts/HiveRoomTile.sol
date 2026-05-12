// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title HiveRoomTile
 * @notice HiveRoom 방 타일 NFT (ERC-721, UUPS 업그레이드 가능)
 *
 * 핵심 설계:
 * - tokenId = 타일 번호 (1:1 매핑, 타일 1번 = NFT #1)
 * - 타일 소유자만 민팅 가능 (서버 서명으로 소유권 검증)
 * - MARKET_ROLE을 가진 컨트랙트(HiveRoomMarket)만 강제 이전 가능
 * - stake/unstake: 인앱(스테이킹)↔온체인(출고) 이중 구조
 */
contract HiveRoomTile is
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable
{
    using ECDSA for bytes32;
    using Strings for uint256;

    // ─── Roles ───────────────────────────────────────────────────────────
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MARKET_ROLE   = keccak256("MARKET_ROLE");
    bytes32 public constant STAKER_ROLE   = keccak256("STAKER_ROLE");

    // EIP-712 타입해시
    bytes32 private constant MINT_TYPEHASH = keccak256(
        "Mint(address user,uint256 tileNumber,uint256 nonce)"
    );

    // ─── 상태 변수 ────────────────────────────────────────────────────────
    address public serverSigner;                        // 서버 서명자 주소
    string  public baseMetadataURI;                     // IPFS 기본 URI
    mapping(uint256 => bool)    public minted;          // 민팅 여부
    mapping(address => uint256) public mintNonce;       // 재사용 방지 nonce
    mapping(uint256 => address) public stakedBy;        // 스테이킹한 원래 소유자

    // ─── 이벤트 ──────────────────────────────────────────────────────────
    event TileMinted(uint256 indexed tileNumber, address indexed owner);
    event TileForceTransferred(uint256 indexed tileNumber, address indexed from, address indexed to);
    event TileStaked(uint256 indexed tokenId, address indexed staker);
    event TileUnstaked(uint256 indexed tokenId, address indexed to);
    event ServerSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event BaseURIUpdated(string newBaseURI);

    // ─── 초기화 ──────────────────────────────────────────────────────────
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _serverSigner,
        string  calldata _baseMetadataURI
    ) external initializer {
        __ERC721_init("HiveRoom Tile", "HRTILE");
        __AccessControl_init();
        __EIP712_init("HiveRoomTile", "1");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        serverSigner    = _serverSigner;
        baseMetadataURI = _baseMetadataURI;
    }

    // ─── 핵심 기능 ────────────────────────────────────────────────────────

    /**
     * @notice 타일 NFT 민팅 (서버가 서명 후 발급; recipient 지갑으로 바로 발행)
     * @param tileNumber 타일 번호 (= tokenId)
     * @param recipient  NFT를 받을 지갑 주소
     * @param signature  서버가 발급한 ECDSA 서명
     */
    function mint(uint256 tileNumber, address recipient, bytes calldata signature) external {
        require(tileNumber > 0, "HiveRoomTile: invalid tile number");
        require(!minted[tileNumber], "HiveRoomTile: already minted");
        require(recipient != address(0), "HiveRoomTile: zero recipient");

        address user = recipient;

        // 서버 서명 검증
        bytes32 structHash = keccak256(
            abi.encode(MINT_TYPEHASH, user, tileNumber, mintNonce[user])
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = digest.recover(signature);
        require(recovered == serverSigner, "HiveRoomTile: invalid server signature");

        // 상태 업데이트
        mintNonce[user]++;
        minted[tileNumber] = true;

        // NFT 발행
        _safeMint(recipient, tileNumber);

        emit TileMinted(tileNumber, recipient);
    }

    /**
     * @notice 타일 NFT 스테이킹 (온체인 → 인앱)
     * @dev 유저가 직접 호출; NFT를 컨트랙트가 보관
     * @param tokenId 스테이킹할 타일 번호
     */
    function stake(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "HiveRoomTile: not owner");
        stakedBy[tokenId] = msg.sender;
        _transfer(msg.sender, address(this), tokenId);
        emit TileStaked(tokenId, msg.sender);
    }

    /**
     * @notice 타일 NFT 언스테이킹 (인앱 → 온체인)
     * @dev STAKER_ROLE 보유자(서버)만 호출 가능
     * @param tokenId 언스테이킹할 타일 번호
     * @param to      NFT를 받을 지갑 주소
     */
    function unstake(uint256 tokenId, address to) external onlyRole(STAKER_ROLE) {
        require(ownerOf(tokenId) == address(this), "HiveRoomTile: not staked");
        require(to != address(0), "HiveRoomTile: zero address");
        delete stakedBy[tokenId];
        _transfer(address(this), to, tokenId);
        emit TileUnstaked(tokenId, to);
    }

    /**
     * @notice 타일 NFT 강제 이전 (타일 구매 시)
     * @param from 현재 소유자
     * @param to   새 소유자
     * @param tokenId 타일 번호
     *
     * MARKET_ROLE을 가진 HiveRoomMarket 컨트랙트만 호출 가능.
     */
    function forceTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external onlyRole(MARKET_ROLE) {
        require(ownerOf(tokenId) == from, "HiveRoomTile: from is not owner");
        require(to != address(0), "HiveRoomTile: transfer to zero address");

        _transfer(from, to, tokenId);

        emit TileForceTransferred(tokenId, from, to);
    }

    /**
     * @notice 타일 NFT 전체 상태 조회 (프론트엔드용)
     * @param tokenId 타일 번호
     * @return isMinted   민팅 여부
     * @return isStaked   현재 스테이킹(컨트랙트 보관) 여부
     * @return currentOwner 현재 소유자 (미민팅 시 address(0))
     */
    function tileNftStatus(uint256 tokenId) external view returns (
        bool isMinted,
        bool isStaked,
        address currentOwner
    ) {
        isMinted = minted[tokenId];
        if (isMinted) {
            currentOwner = ownerOf(tokenId);
            isStaked = (currentOwner == address(this));
        }
    }

    /**
     * @notice 타일 NFT 존재 여부 및 소유자 확인 (프론트엔드용)
     */
    function tileInfo(uint256 tileNumber) external view returns (bool exists, address owner) {
        exists = minted[tileNumber];
        owner  = exists ? ownerOf(tileNumber) : address(0);
    }

    // ─── 메타데이터 ───────────────────────────────────────────────────────

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(minted[tokenId], "HiveRoomTile: token does not exist");
        return string(abi.encodePacked(baseMetadataURI, tokenId.toString(), ".json"));
    }

    // ─── 관리자 기능 ──────────────────────────────────────────────────────

    function setServerSigner(address _newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newSigner != address(0), "HiveRoomTile: zero address");
        emit ServerSignerUpdated(serverSigner, _newSigner);
        serverSigner = _newSigner;
    }

    function setBaseMetadataURI(string calldata _newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseMetadataURI = _newURI;
        emit BaseURIUpdated(_newURI);
    }

    function getMintNonce(address user) external view returns (uint256) {
        return mintNonce[user];
    }

    // ─── 인터페이스 지원 ──────────────────────────────────────────────────
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ─── UUPS 업그레이드 가드 ─────────────────────────────────────────────
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}
