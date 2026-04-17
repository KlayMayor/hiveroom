import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { ethers } from 'npm:ethers@5.7.2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const HIVE_ADDRESS = '0xE46AfBa60F86D34F110d5ADC5Ea763dB883096dE';
const CHAIN_ID     = 11124; // Abstract Testnet
const RPC_URL      = 'https://api.testnet.abs.xyz';
const CLAIM_MIN    = 5_000;

const NONCE_ABI = ['function getClaimNonce(address user) external view returns (uint256)'];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return err(401, 'Unauthorized');

    // Verify Supabase JWT
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user?.email) return err(401, 'Unauthorized');

    const { wallet, amount } = await req.json();
    if (!wallet || !amount) return err(400, 'Missing wallet or amount');
    if (!ethers.utils.isAddress(wallet)) return err(400, 'Invalid wallet address');
    if (Number(amount) < CLAIM_MIN) return err(400, `Minimum claim is ${CLAIM_MIN} HIVE`);

    // Check in-app balance
    const { data: balRow } = await supabase
      .from('user_balances')
      .select('balance')
      .eq('email', user.email)
      .single();
    if (!balRow) return err(404, 'Balance not found');
    if (balRow.balance < Number(amount)) return err(400, 'Insufficient in-app balance');

    // Read on-chain claim nonce
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const hive = new ethers.Contract(HIVE_ADDRESS, NONCE_ABI, provider);
    const nonce = await hive.getClaimNonce(wallet);

    // EIP-712 sign
    const signer = new ethers.Wallet(Deno.env.get('SERVER_SIGNER_PRIVATE_KEY')!);
    const signature = await signer._signTypedData(
      { name: 'HIVEToken', version: '1', chainId: CHAIN_ID, verifyingContract: HIVE_ADDRESS },
      { Claim: [
          { name: 'user',   type: 'address' },
          { name: 'amount', type: 'uint256' },
          { name: 'nonce',  type: 'uint256' },
        ]
      },
      { user: wallet, amount: ethers.utils.parseEther(String(amount)), nonce }
    );

    return json({ signature });
  } catch (e) {
    console.error(e);
    return err(500, String(e));
  }
});

const err  = (s: number, m: string) => new Response(m, { status: s, headers: CORS });
const json = (d: unknown) => new Response(JSON.stringify(d), { headers: { ...CORS, 'Content-Type': 'application/json' } });
