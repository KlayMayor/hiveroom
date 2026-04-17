import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { ethers } from 'npm:ethers@5.7.2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const TILE_ADDRESS = '0x175D30A5027BFb3C28F6ACA47FA5B95f912ad162';
const CHAIN_ID     = 11124;
const RPC_URL      = 'https://api.testnet.abs.xyz';

const TILE_ABI = [
  'function getMintNonce(address user) external view returns (uint256)',
  'function minted(uint256 tokenId) external view returns (bool)',
];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return err(401, 'Unauthorized');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user?.email) return err(401, 'Unauthorized');

    const { wallet, tileNumber } = await req.json();
    if (!wallet || tileNumber === undefined) return err(400, 'Missing wallet or tileNumber');
    if (!ethers.utils.isAddress(wallet)) return err(400, 'Invalid wallet address');

    // Verify ownership in Supabase
    const { data: roomRow } = await supabase
      .from('rooms')
      .select('email')
      .eq('room_number', Number(tileNumber))
      .single();
    if (!roomRow) return err(404, 'Room not found');
    if (roomRow.email.toLowerCase() !== user.email.toLowerCase()) return err(403, 'You do not own this tile');

    // Check on-chain state
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const tile = new ethers.Contract(TILE_ADDRESS, TILE_ABI, provider);
    const [isMinted, nonce] = await Promise.all([
      tile.minted(Number(tileNumber)),
      tile.getMintNonce(wallet),
    ]);
    if (isMinted) return err(400, 'NFT already minted');

    // EIP-712 sign
    const signer = new ethers.Wallet(Deno.env.get('SERVER_SIGNER_PRIVATE_KEY')!);
    const signature = await signer._signTypedData(
      { name: 'HiveRoomTile', version: '1', chainId: CHAIN_ID, verifyingContract: TILE_ADDRESS },
      { Mint: [
          { name: 'user',       type: 'address' },
          { name: 'tileNumber', type: 'uint256' },
          { name: 'nonce',      type: 'uint256' },
        ]
      },
      { user: wallet, tileNumber: Number(tileNumber), nonce }
    );

    return json({ signature });
  } catch (e) {
    console.error(e);
    return err(500, String(e));
  }
});

const err  = (s: number, m: string) => new Response(m, { status: s, headers: CORS });
const json = (d: unknown) => new Response(JSON.stringify(d), { headers: { ...CORS, 'Content-Type': 'application/json' } });
