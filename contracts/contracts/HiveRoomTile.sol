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
 * - 이미지/꾸미기 데이터는 Supabase에 저장, NFT에는 타일 번호·ZONE만 기록
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

    // EIP-712 타입해시
    bytes32 private constant MINT_TYPEHASH = keccak256(
        "Mint(address user,uint256 tileNumber,uint256 nonce)"
    );

    // ─── 상태 변수 ────────────────────────────────────────────────────────
    address public serverSigner;                        // 서버 서명자 주소
    string  public baseMetadataURI;                     // IPFS 기본 URI
    mapping(uint256 => bool)    public minted;          // 민팅 여부
    mapping(address => uint256) public mintNonce;       // 재사용 방지 nonce

    // ─── 이벤트 ──────────────────────────────────────────────────────────
    event TileMinted(uint256 indexed tileNumber, address indexed owner);
    event TileForceTransferred(uint256 indexed tileNumber, address indexed from, address indexed to);
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
     * @notice 타일 NFT 민팅
     * @param tileNumber 타일 번호 (= tokenId)
     * @param signature 서버가 발급한 ECDSA 서명
     *
     * 호출 조건:
     * - 해당 타일이 아직 민팅되지 않아야 함
     * - 서버 서명 검증 통과 (Supabase에서 ownerEmail 확인 후 발급)
     */
    function mint(uint256 tileNumber, bytes calldata signature) external {
        require(tileNumber > 0, "HiveRoomTile: invalid tile number");
        require(!minted[tileNumber], "HiveRoomTile: already minted");

        address user = msg.sender;

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
        _safeMint(user, tileNumber);

        emit TileMinted(tileNumber, user);
    }

    /**
     * @notice 타일 NFT 강제 이전 (타일 구매 시)
     * @param from 현재 소유자
     * @param to   새 소유자
     * @param tokenId 타일 번호
     *
     * MARKET_ROLE을 가진 HiveRoomMarket 컨트랙트만 호출 가능.
     * 표준 ERC-721 approve 없이 강제 이전.
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
     * @notice 타일 NFT 존재 여부 및 소유자 확인 (프론트엔드용)
     * @return exists NFT 민팅 여부
     * @return owner  현재 소유자 (미민팅 시 address(0))
     */
    function tileInfo(uint256 tileNumber) external view returns (bool exists, address owner) {
        exists = minted[tileNumber];
        owner  = exists ? ownerOf(tileNumber) : address(0);
    }

    // ─── 메타데이터 ───────────────────────────────────────────────────────

    /**
     * @notice NFT 메타데이터 URI
     * 예) ipfs://QmXxx.../1.json
     * 메타데이터 내용: tileNumber, zone, name, image
     */
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
