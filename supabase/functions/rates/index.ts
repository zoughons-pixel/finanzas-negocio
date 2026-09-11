// Supabase Edge Function: rates
// Devuelve BCV USD/VES y costo neto Airtm para comprar USD/USDC con VES.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function fetchWithTimeout(url: string, init: RequestInit = {}, timeoutMs = 8000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function fetchBCV() {
  const res = await fetchWithTimeout("https://bcv.today/api/v1/rate.json", {
    headers: { "Cache-Control": "no-cache", "Accept": "application/json" },
  });
  if (!res.ok) throw new Error(`BCV HTTP ${res.status}`);
  const data = await res.json();
  const rate = Number(data?.USD);
  if (!(rate > 0)) throw new Error("Tasa BCV inválida");
  return {
    rate,
    effectiveDate: data.effective_date ?? data.date ?? null,
    updatedAt: data.updated_at ?? null,
    source: "BCV Today · datos de bcv.org.ve",
  };
}

async function fetchAirtm() {
  const res = await fetchWithTimeout("https://rates.airtm.io/", {
    headers: { "Accept": "application/json", "Cache-Control": "no-cache" },
  });
  if (!res.ok) throw new Error(`Airtm rates HTTP ${res.status}`);

  const payload = await res.json();
  const vesUsd = payload?.data?.["ves/usd"];
  const addValue = Number(vesUsd?.addValue);
  const withdrawValue = Number(vesUsd?.withdrawValue);

  if (!(addValue > 0)) throw new Error("Tasa Airtm VES/USD inválida");

  return {
    rate: addValue,
    withdrawRate: withdrawValue > 0 ? withdrawValue : null,
    updatedAt: new Date().toISOString(),
    source: "Airtm rates · VES → USD/USDC",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const [bcvR, airtmR] = await Promise.allSettled([fetchBCV(), fetchAirtm()]);
    const bcv = bcvR.status === "fulfilled" ? bcvR.value : { rate: null, error: String(bcvR.reason) };
    const airtm = airtmR.status === "fulfilled" ? airtmR.value : { rate: null, error: String(airtmR.reason) };
    const status = bcv.rate && airtm.rate ? 200 : 206;

    return new Response(JSON.stringify({ fetchedAt: new Date().toISOString(), bcv, airtm }), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
