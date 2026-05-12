import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet, Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

// UUPS upgrade: deploys new HiveRoomTile implementation and upgrades proxy
// Proxy address stays the same — only implementation changes
export default async function (hre: HardhatRuntimeEnvironment) {
  const provider = new Provider(hre.network.config.url);
  const wallet = new Wallet(process.env.PRIVATE_KEY!, provider);
  // Use the actual live proxy address (frontend ONCHAIN.TILE)
  const proxyAddress = process.env.HIVE_ROOM_TILE_ADDRESS || '0x175D30A5027BFb3C28F6ACA47FA5B95f912ad162';
  const serverSigner = process.env.SERVER_SIGNER_ADDRESS!;

  if (!proxyAddress) throw new Error("HIVE_ROOM_TILE_ADDRESS not set in .env");

  console.log("Upgrading HiveRoomTile (UUPS)...");
  console.log("  Deployer  :", wallet.address);
  console.log("  Proxy     :", proxyAddress);

  // 1. Deploy new implementation
  const implArtifact = await hre.deployer.loadArtifact("HiveRoomTile");
  const implContract = await hre.deployer.deploy(implArtifact, []);
  await implContract.waitForDeployment();
  const newImplAddress = await implContract.getAddress();
  console.log("  New impl  :", newImplAddress);

  // 2. Call upgradeToAndCall on the existing proxy
  const upgradeABI = [
    "function upgradeToAndCall(address newImplementation, bytes calldata data) external payable",
    "function grantRole(bytes32 role, address account) external",
  ];
  const proxy = new ethers.Contract(proxyAddress, upgradeABI, wallet as any);

  const upgradeTx = await proxy.upgradeToAndCall(newImplAddress, "0x");
  await upgradeTx.wait();
  console.log("  Upgraded! tx:", upgradeTx.hash);

  // 3. Grant STAKER_ROLE to the server signer so it can call unstake()
  const STAKER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("STAKER_ROLE"));
  const roleTx = await proxy.grantRole(STAKER_ROLE, serverSigner);
  await roleTx.wait();
  console.log("  STAKER_ROLE granted to:", serverSigner, "tx:", roleTx.hash);

  console.log("✅ HiveRoomTile upgrade complete. Proxy:", proxyAddress);
}
