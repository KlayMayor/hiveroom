import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet } from "zksync-ethers";
import * as dotenv from "dotenv";

dotenv.config();

export default async function (hre: HardhatRuntimeEnvironment) {
  const wallet = new Wallet(process.env.PRIVATE_KEY!);
  const serverSigner = process.env.SERVER_SIGNER_ADDRESS!;
  const baseMetadataURI = process.env.BASE_METADATA_URI
    || "https://hiveroom.vercel.app/api/metadata/";

  console.log("Deploying HiveRoomTile...");
  console.log("  Deployer    :", wallet.address);
  console.log("  ServerSigner:", serverSigner);
  console.log("  BaseURI     :", baseMetadataURI);

  const artifact = await hre.deployer.loadArtifact("HiveRoomTile");

  const proxy = await hre.zkUpgrades.deployProxy(
    wallet,
    artifact,
    [serverSigner, baseMetadataURI],
    { kind: "uups" }
  );

  await proxy.waitForDeployment();
  const address = await proxy.getAddress();

  console.log("✅ HiveRoomTile deployed to:", address);
  console.log("   → Add to .env: HIVE_ROOM_TILE_ADDRESS=" + address);

  return address;
}
