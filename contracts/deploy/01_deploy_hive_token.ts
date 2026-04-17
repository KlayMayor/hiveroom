import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet } from "zksync-ethers";
import * as dotenv from "dotenv";

dotenv.config();

export default async function (hre: HardhatRuntimeEnvironment) {
  const wallet = new Wallet(process.env.PRIVATE_KEY!);
  const serverSigner = process.env.SERVER_SIGNER_ADDRESS!;

  if (!serverSigner) {
    throw new Error("SERVER_SIGNER_ADDRESS not set in .env");
  }

  console.log("Deploying HIVEToken...");
  console.log("  Deployer    :", wallet.address);
  console.log("  ServerSigner:", serverSigner);
  console.log("  Network     :", hre.network.name);

  const artifact = await hre.deployer.loadArtifact("HIVEToken");

  const proxy = await hre.zkUpgrades.deployProxy(
    wallet,
    artifact,
    [serverSigner],
    { kind: "uups" }
  );

  await proxy.waitForDeployment();
  const address = await proxy.getAddress();

  console.log("✅ HIVEToken deployed to:", address);
  console.log("   → Add to .env: HIVE_TOKEN_ADDRESS=" + address);

  return address;
}
