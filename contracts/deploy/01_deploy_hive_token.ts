import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet, Provider, ContractFactory } from "zksync-ethers";
import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

export default async function (hre: HardhatRuntimeEnvironment) {
  const provider = new Provider(hre.network.config.url);
  const wallet = new Wallet(process.env.PRIVATE_KEY!, provider);
  const serverSigner = process.env.SERVER_SIGNER_ADDRESS!;

  if (!serverSigner) {
    throw new Error("SERVER_SIGNER_ADDRESS not set in .env");
  }

  console.log("Deploying HIVEToken (manual UUPS)...");
  console.log("  Deployer    :", wallet.address);
  console.log("  ServerSigner:", serverSigner);

  // 1. Deploy implementation
  const implArtifact = await hre.deployer.loadArtifact("HIVEToken");
  const implContract = await hre.deployer.deploy(implArtifact, []);
  await implContract.waitForDeployment();
  const implAddress = await implContract.getAddress();
  console.log("  Implementation:", implAddress);

  // 2. Encode initialize calldata
  const iface = new ethers.Interface(implArtifact.abi);
  const initData = iface.encodeFunctionData("initialize", [serverSigner]);

  // 3. Deploy ERC1967Proxy
  const proxyArtifact = await hre.deployer.loadArtifact("ERC1967Proxy");
  const proxyContract = await hre.deployer.deploy(proxyArtifact, [implAddress, initData]);
  await proxyContract.waitForDeployment();
  const proxyAddress = await proxyContract.getAddress();

  console.log("✅ HIVEToken proxy deployed to:", proxyAddress);
  console.log("   → Add to .env: HIVE_TOKEN_ADDRESS=" + proxyAddress);

  return proxyAddress;
}
