import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet, Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

export default async function (hre: HardhatRuntimeEnvironment) {
  const provider = new Provider(hre.network.config.url);
  const wallet = new Wallet(process.env.PRIVATE_KEY!, provider);
  const serverSigner = process.env.SERVER_SIGNER_ADDRESS!;
  const hiveAddress  = process.env.HIVE_TOKEN_ADDRESS!;
  const tileAddress  = process.env.HIVE_ROOM_TILE_ADDRESS!;

  if (!hiveAddress || !tileAddress) {
    throw new Error("HIVE_TOKEN_ADDRESS or HIVE_ROOM_TILE_ADDRESS not set in .env");
  }

  console.log("Deploying HiveRoomMarket (manual UUPS)...");
  console.log("  HIVEToken    :", hiveAddress);
  console.log("  HiveRoomTile :", tileAddress);
  console.log("  ServerSigner :", serverSigner);

  const implArtifact = await hre.deployer.loadArtifact("HiveRoomMarket");
  const implContract = await hre.deployer.deploy(implArtifact, []);
  await implContract.waitForDeployment();
  const implAddress = await implContract.getAddress();
  console.log("  Implementation:", implAddress);

  const iface = new ethers.Interface(implArtifact.abi);
  const initData = iface.encodeFunctionData("initialize", [hiveAddress, tileAddress, serverSigner]);

  const proxyArtifact = await hre.deployer.loadArtifact("ERC1967Proxy");
  const proxyContract = await hre.deployer.deploy(proxyArtifact, [implAddress, initData]);
  await proxyContract.waitForDeployment();
  const marketAddress = await proxyContract.getAddress();
  console.log("✅ HiveRoomMarket proxy deployed to:", marketAddress);

  // Grant MARKET_ROLE on HiveRoomTile
  console.log("\nGranting MARKET_ROLE to HiveRoomMarket on HiveRoomTile...");
  const tileABI = [
    "function grantRole(bytes32 role, address account) external",
    "function MARKET_ROLE() external view returns (bytes32)",
  ];
  const tileContract = new ethers.Contract(tileAddress, tileABI, wallet);
  const MARKET_ROLE = await tileContract.MARKET_ROLE();
  const grantTx = await tileContract.grantRole(MARKET_ROLE, marketAddress);
  await grantTx.wait();
  console.log("✅ MARKET_ROLE granted");

  console.log("\n   → Add to .env: HIVE_ROOM_MARKET_ADDRESS=" + marketAddress);
  return marketAddress;
}
