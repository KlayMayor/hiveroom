import { deployProxy } from "@matterlabs/hardhat-zksync-upgradable";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet, Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * HiveRoomMarket (UUPS Proxy) 배포 + 권한 설정 스크립트
 *
 * 실행:
 *   npx hardhat deploy-zksync --script deploy/03_deploy_market.ts --network abstractTestnet
 *
 * 사전 조건:
 *   HIVE_TOKEN_ADDRESS, HIVE_ROOM_TILE_ADDRESS 설정 필요
 */
export default async function (hre: HardhatRuntimeEnvironment) {
  const provider = new Provider(hre.network.config.url);
  const wallet = new Wallet(process.env.PRIVATE_KEY!, provider);
  const serverSigner   = process.env.SERVER_SIGNER_ADDRESS!;
  const hiveAddress    = process.env.HIVE_TOKEN_ADDRESS!;
  const tileAddress    = process.env.HIVE_ROOM_TILE_ADDRESS!;

  if (!hiveAddress || !tileAddress) {
    throw new Error("HIVE_TOKEN_ADDRESS or HIVE_ROOM_TILE_ADDRESS not set in .env");
  }

  console.log("Deploying HiveRoomMarket...");
  console.log("  HIVEToken    :", hiveAddress);
  console.log("  HiveRoomTile :", tileAddress);
  console.log("  ServerSigner :", serverSigner);

  const artifact = await hre.deployer.loadArtifact("HiveRoomMarket");

  const proxy = await deployProxy(
    hre,
    artifact,
    [hiveAddress, tileAddress, serverSigner],
    { wallet, kind: "uups" }
  );

  await proxy.waitForDeployment();
  const marketAddress = await proxy.getAddress();
  console.log("✅ HiveRoomMarket deployed to:", marketAddress);

  // ─── HiveRoomTile에 MARKET_ROLE 부여 ─────────────────────────────────
  console.log("\nGranting MARKET_ROLE to HiveRoomMarket on HiveRoomTile...");

  const tileABI = [
    "function grantRole(bytes32 role, address account) external",
    "function MARKET_ROLE() external view returns (bytes32)",
  ];
  const tileContract = new ethers.Contract(tileAddress, tileABI, wallet);
  const MARKET_ROLE = await tileContract.MARKET_ROLE();
  const grantTx = await tileContract.grantRole(MARKET_ROLE, marketAddress);
  await grantTx.wait();
  console.log("✅ MARKET_ROLE granted to Market on Tile contract");

  console.log("\n   → Add to .env: HIVE_ROOM_MARKET_ADDRESS=" + marketAddress);

  return marketAddress;
}
