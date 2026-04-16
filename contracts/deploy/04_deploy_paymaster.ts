import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet, Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * HiveRoomPaymaster 배포 + 허용 컨트랙트 등록 스크립트
 *
 * 실행:
 *   npx hardhat deploy-zksync --script deploy/04_deploy_paymaster.ts --network abstractTestnet
 *
 * 사전 조건:
 *   HIVE_TOKEN_ADDRESS, HIVE_ROOM_TILE_ADDRESS, HIVE_ROOM_MARKET_ADDRESS 설정 필요
 *
 * Paymaster 초기 충전: 이 스크립트에서 0.01 ETH를 자동 입금
 * 운영 예산 $100 상당의 ETH를 별도로 추가 충전하세요.
 */
export default async function (hre: HardhatRuntimeEnvironment) {
  const provider    = new Provider(hre.network.config.url);
  const wallet      = new Wallet(process.env.PRIVATE_KEY!, provider);
  const hiveAddress   = process.env.HIVE_TOKEN_ADDRESS!;
  const tileAddress   = process.env.HIVE_ROOM_TILE_ADDRESS!;
  const marketAddress = process.env.HIVE_ROOM_MARKET_ADDRESS!;

  if (!hiveAddress || !tileAddress || !marketAddress) {
    throw new Error("Contract addresses not fully set in .env");
  }

  console.log("Deploying HiveRoomPaymaster...");

  const artifact = await hre.deployer.loadArtifact("HiveRoomPaymaster");
  const paymaster = await hre.deployer.deploy(artifact, [wallet.address]);
  await paymaster.waitForDeployment();
  const paymasterAddress = await paymaster.getAddress();

  console.log("✅ HiveRoomPaymaster deployed to:", paymasterAddress);

  // ─── 허용 컨트랙트 등록 ──────────────────────────────────────────────
  const paymasterABI = [
    "function setAllowedContract(address _contract, bool _allowed) external",
  ];
  const paymasterContract = new ethers.Contract(paymasterAddress, paymasterABI, wallet);

  console.log("\nWhitelisting HiveRoom contracts...");
  for (const [name, addr] of [
    ["HIVEToken",      hiveAddress],
    ["HiveRoomTile",   tileAddress],
    ["HiveRoomMarket", marketAddress],
  ]) {
    const tx = await paymasterContract.setAllowedContract(addr, true);
    await tx.wait();
    console.log(`  ✅ ${name} (${addr}) whitelisted`);
  }

  // ─── 초기 ETH 충전 (0.01 ETH) ────────────────────────────────────────
  console.log("\nDepositing initial ETH to Paymaster...");
  const depositTx = await wallet.sendTransaction({
    to: paymasterAddress,
    value: ethers.parseEther("0.01"),
  });
  await depositTx.wait();
  console.log("  ✅ 0.01 ETH deposited");
  console.log("  ⚠️  Add $100 worth of ETH to cover ~100,000 transactions");

  console.log("\n   → Add to .env: PAYMASTER_ADDRESS=" + paymasterAddress);

  return paymasterAddress;
}
