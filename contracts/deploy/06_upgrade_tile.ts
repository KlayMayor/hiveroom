import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet, Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * HiveRoomTile UUPS 업그레이드 — 새 구현체 배포 후 프록시에 연결
 * 프록시 주소(HIVE_ROOM_TILE_ADDRESS) 그대로 유지됨
 *
 * 실행:
 *   npx hardhat deploy-zksync --script 06_upgrade_tile.ts --network abstractTestnet
 */
export default async function (hre: HardhatRuntimeEnvironment) {
  const provider     = new Provider(hre.network.config.url);
  const wallet       = new Wallet(process.env.PRIVATE_KEY!, provider);
  const proxyAddress = process.env.HIVE_ROOM_TILE_ADDRESS!;

  if (!proxyAddress) throw new Error("HIVE_ROOM_TILE_ADDRESS not set in .env");

  console.log("Upgrading HiveRoomTile implementation...");
  console.log("  Deployer :", wallet.address);
  console.log("  Proxy    :", proxyAddress);

  // Deploy new implementation
  const implArtifact  = await hre.deployer.loadArtifact("HiveRoomTile");
  const implContract  = await hre.deployer.deploy(implArtifact, []);
  await implContract.waitForDeployment();
  const newImplAddress = await implContract.getAddress();
  console.log("  New impl :", newImplAddress);

  // Call upgradeToAndCall on the proxy (UUPS)
  const upgradeABI = ["function upgradeToAndCall(address newImplementation, bytes calldata data) external"];
  const proxy = new ethers.Contract(proxyAddress, upgradeABI, wallet);
  const tx = await proxy.upgradeToAndCall(newImplAddress, "0x");
  await tx.wait();

  console.log("✅ Upgrade complete — proxy", proxyAddress, "now points to", newImplAddress);
}
