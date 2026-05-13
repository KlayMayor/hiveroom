import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet, Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * HiveRoomTile baseMetadataURI 업데이트
 *
 * 실행:
 *   npx hardhat deploy-zksync --script 07_set_metadata_uri.ts --network abstractTestnet
 */
export default async function (hre: HardhatRuntimeEnvironment) {
  const provider     = new Provider(hre.network.config.url);
  const wallet       = new Wallet(process.env.PRIVATE_KEY!, provider);
  const proxyAddress = process.env.HIVE_ROOM_TILE_ADDRESS!;
  const newBaseURI   = process.env.METADATA_BASE_URI!;

  if (!proxyAddress) throw new Error("HIVE_ROOM_TILE_ADDRESS not set in .env");
  if (!newBaseURI)   throw new Error("METADATA_BASE_URI not set in .env");

  console.log("Setting baseMetadataURI...");
  console.log("  Proxy  :", proxyAddress);
  console.log("  New URI:", newBaseURI);

  const abi = ["function setBaseMetadataURI(string calldata _newURI) external"];
  const tile = new ethers.Contract(proxyAddress, abi, wallet);
  const tx = await tile.setBaseMetadataURI(newBaseURI);
  await tx.wait();

  console.log("✅ baseMetadataURI updated to:", newBaseURI);
}
