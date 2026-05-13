const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function getZone(tileNumber: number): number {
  if (tileNumber <= 37) return 1;
  if (tileNumber <= 91) return 2;
  return 3;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  // URL 마지막 세그먼트에서 tokenId 추출: .../nft-metadata/42.json → 42
  const url = new URL(req.url);
  const segments = url.pathname.split('/');
  const last = segments[segments.length - 1]; // e.g. "42.json"
  const idStr = last.replace(/\.json$/i, '');
  const tokenId = parseInt(idStr, 10);

  if (!tokenId || isNaN(tokenId) || tokenId < 1 || tokenId > 1027) {
    return new Response(JSON.stringify({ error: 'Invalid token ID' }), {
      status: 400,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }

  const zone = getZone(tokenId);

  const metadata = {
    name: `Tile no. ${tokenId}`,
    description: `HiveRoom Tile NFT #${tokenId}`,
    attributes: [
      { trait_type: 'Tile Number', value: tokenId },
      { trait_type: 'Zone',        value: zone     },
    ],
  };

  return new Response(JSON.stringify(metadata), {
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
});
