import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet, Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * 새로운 HiveRoomTile 주소를 HiveRoomPaymaster 화이트리스트에 등록
 *
 * 실행:
 *   npx hardhat deploy-zksync --script deploy/05_whitelist_tile.ts --network abstractTestnet
 */
export default async function (hre: HardhatRuntimeEnvironment) {
  const provider       = new Provider(hre.network.config.url);
  const wallet         = new Wallet(process.env.PRIVATE_KEY!, provider);
  const paymasterAddr  = process.env.PAYMASTER_ADDRESS!;
  const tileAddr       = process.env.HIVE_ROOM_TILE_ADDRESS!;

  if (!paymasterAddr || !tileAddr) {
    throw new Error("PAYMASTER_ADDRESS and HIVE_ROOM_TILE_ADDRESS must be set in .env");
  }

  console.log("Whitelisting HiveRoomTile in paymaster...");
  console.log("  Paymaster :", paymasterAddr);
  console.log("  New Tile  :", tileAddr);

  const paymasterABI = ["function setAllowedContract(address _contract, bool _allowed) external"];
  const paymaster = new ethers.Contract(paymasterAddr, paymasterABI, wallet);
  const tx = await paymaster.setAllowedContract(tileAddr, true);
  await tx.wait();

  console.log("✅ Done — new HiveRoomTile is now whitelisted in the paymaster");
}
