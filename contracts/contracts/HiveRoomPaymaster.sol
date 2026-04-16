// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title HiveRoomPaymaster
 * @notice HiveRoom 전용 가스비 대납 컨트랙트 (Abstract / ZKsync 네이티브)
 *
 * 역할:
 * - HiveRoom 컨트랙트(HIVEToken, HiveRoomTile, HiveRoomMarket) 호출 시
 *   유저의 가스비를 플랫폼이 전액 대납
 * - 유저는 ETH 없이도 트랜잭션 전송 가능
 *
 * 운영 예산: $100 (Abstract ETH 기준 약 10만 트랜잭션)
 * 재충전: owner가 ETH를 직접 deposit
 *
 * 주의: 이 컨트랙트는 단순 구조이므로 UUPS 불필요. 재배포 비용 무시.
 */
contract HiveRoomPaymaster is IPaymaster, Ownable {

    // ─── 허용 컨트랙트 목록 ───────────────────────────────────────────────
    mapping(address => bool) public allowedContracts;

    // ─── 이벤트 ──────────────────────────────────────────────────────────
    event ContractAllowed(address indexed contractAddress, bool allowed);
    event FundsDeposited(address indexed from, uint256 amount);
    event FundsWithdrawn(address indexed to, uint256 amount);

    // ─── 생성자 ──────────────────────────────────────────────────────────
    constructor(address _owner) Ownable(_owner) {}

    // ─── 허용 컨트랙트 관리 ───────────────────────────────────────────────

    /// @notice HiveRoom 컨트랙트 주소를 허용 목록에 추가/제거
    function setAllowedContract(address _contract, bool _allowed) external onlyOwner {
        allowedContracts[_contract] = _allowed;
        emit ContractAllowed(_contract, _allowed);
    }

    // ─── IPaymaster 구현 ──────────────────────────────────────────────────

    /**
     * @notice 트랜잭션 가스비 대납 검증
     * 허용된 HiveRoom 컨트랙트 호출만 대납
     */
    function validateAndPayForPaymasterTransaction(
        bytes32,           // _txHash (미사용)
        bytes32,           // _suggestedSignedHash (미사용)
        Transaction calldata _transaction
    ) external payable override onlyBootloader returns (bytes4 magic, bytes memory context) {

        // General Flow 확인 (기본 Paymaster 흐름)
        require(
            _transaction.paymasterInput.length >= 4,
            "HiveRoomPaymaster: invalid paymaster input"
        );
        bytes4 paymasterInputSelector = bytes4(_transaction.paymasterInput[0:4]);
        require(
            paymasterInputSelector == IPaymasterFlow.general.selector,
            "HiveRoomPaymaster: unsupported paymaster flow"
        );

        // 허용된 컨트랙트만 대납
        address targetContract = address(uint160(_transaction.to));
        require(
            allowedContracts[targetContract],
            "HiveRoomPaymaster: contract not whitelisted"
        );

        // 가스비 계산 및 BOOTLOADER에 ETH 전송
        uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;
        require(
            address(this).balance >= requiredETH,
            "HiveRoomPaymaster: insufficient balance"
        );

        (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{value: requiredETH}("");
        require(success, "HiveRoomPaymaster: ETH transfer to bootloader failed");

        magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
        context = "";
    }

    /**
     * @notice 트랜잭션 후처리 (환급 등)
     * 현재 구현에서는 별도 처리 없음
     */
    function postTransaction(
        bytes calldata,           // _context
        Transaction calldata,     // _transaction
        bytes32,                  // _txHash
        bytes32,                  // _suggestedSignedHash
        ExecutionResult,          // _txResult
        uint256                   // _maxRefundedGas
    ) external payable override onlyBootloader {}

    // ─── 자금 관리 ────────────────────────────────────────────────────────

    /// @notice ETH 입금 (운영 자금 충전)
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }

    /// @notice 잔액 조회
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice ETH 출금 (긴급 회수)
    function withdraw(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "HiveRoomPaymaster: insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "HiveRoomPaymaster: withdraw failed");
        emit FundsWithdrawn(owner(), amount);
    }

    // ─── Bootloader 전용 modifier ─────────────────────────────────────────
    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "HiveRoomPaymaster: only bootloader"
        );
        _;
    }
}
