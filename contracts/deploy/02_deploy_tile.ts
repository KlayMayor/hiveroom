import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet, Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

export default async function (hre: HardhatRuntimeEnvironment) {
  const provider = new Provider(hre.network.config.url);
  const wallet = new Wallet(process.env.PRIVATE_KEY!, provider);
  const serverSigner = process.env.SERVER_SIGNER_ADDRESS!;
  const baseMetadataURI = process.env.BASE_METADATA_URI
    || "https://hiveroom.vercel.app/api/metadata/";

  console.log("Deploying HiveRoomTile (manual UUPS)...");
  console.log("  Deployer    :", wallet.address);
  console.log("  ServerSigner:", serverSigner);
  console.log("  BaseURI     :", baseMetadataURI);

  const implArtifact = await hre.deployer.loadArtifact("HiveRoomTile");
  const implContract = await hre.deployer.deploy(implArtifact, []);
  await implContract.waitForDeployment();
  const implAddress = await implContract.getAddress();
  console.log("  Implementation:", implAddress);

  const iface = new ethers.Interface(implArtifact.abi);
  const initData = iface.encodeFunctionData("initialize", [serverSigner, baseMetadataURI]);

  const proxyArtifact = await hre.deployer.loadArtifact("ERC1967Proxy");
  const proxyContract = await hre.deployer.deploy(proxyArtifact, [implAddress, initData]);
  await proxyContract.waitForDeployment();
  const proxyAddress = await proxyContract.getAddress();

  console.log("✅ HiveRoomTile proxy deployed to:", proxyAddress);
  console.log("   → Add to .env: HIVE_ROOM_TILE_ADDRESS=" + proxyAddress);

  // Whitelist new tile address in paymaster if PAYMASTER_ADDRESS is set
  const paymasterAddress = process.env.PAYMASTER_ADDRESS;
  if (paymasterAddress) {
    console.log("\nWhitelisting new tile in HiveRoomPaymaster...");
    const paymasterABI = ["function setAllowedContract(address _contract, bool _allowed) external"];
    const paymaster = new ethers.Contract(paymasterAddress, paymasterABI, wallet);
    const tx = await paymaster.setAllowedContract(proxyAddress, true);
    await tx.wait();
    console.log("  ✅ New HiveRoomTile whitelisted in paymaster");
  }

  return proxyAddress;
}
