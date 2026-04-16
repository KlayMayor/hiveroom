import { deployProxy } from "@matterlabs/hardhat-zksync-upgradable";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet } from "zksync-ethers";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * HiveRoomTile (UUPS Proxy) 배포 스크립트
 *
 * 실행:
 *   npx hardhat deploy-zksync --script deploy/02_deploy_tile.ts --network abstractTestnet
 *
 * 주의: 배포 전 IPFS에 메타데이터 업로드 후 BASE_METADATA_URI 설정
 * 메타데이터 형식: ipfs://QmXxx.../{tileNumber}.json
 */
export default async function (hre: HardhatRuntimeEnvironment) {
  const wallet = new Wallet(process.env.PRIVATE_KEY!);
  const serverSigner = process.env.SERVER_SIGNER_ADDRESS!;

  // 메타데이터 기본 URI (IPFS 또는 서버 URL)
  // 테스트넷: 임시 URL 사용 가능, 메인넷: IPFS 필수
  const baseMetadataURI = process.env.BASE_METADATA_URI
    || "https://hiveroom.vercel.app/api/metadata/";

  console.log("Deploying HiveRoomTile...");
  console.log("  Deployer      :", wallet.address);
  console.log("  ServerSigner  :", serverSigner);
  console.log("  BaseURI       :", baseMetadataURI);

  const artifact = await hre.deployer.loadArtifact("HiveRoomTile");

  const proxy = await deployProxy(hre, artifact, [serverSigner, baseMetadataURI], {
    wallet,
    kind: "uups",
  });

  await proxy.waitForDeployment();
  const address = await proxy.getAddress();

  console.log("✅ HiveRoomTile deployed to:", address);
  console.log("   → Add to .env: HIVE_ROOM_TILE_ADDRESS=" + address);

  return address;
}
