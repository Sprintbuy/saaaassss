import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = (origin: string) => ({
  "Access-Control-Allow-Origin": origin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS, GET",
  "Vary": "Origin",
});

const json = (body: unknown, status: number, origin: string) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });

Deno.serve(async (request) => {
  const url = new URL(request.url);
  const allowed = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map((x) => x.trim()).filter(Boolean);
  const origin = request.headers.get("Origin") ?? "";
  if (request.method === "OPTIONS") {
    if (origin && (!allowed.length || !allowed.includes(origin))) return new Response("Forbidden", { status: 403 });
    return new Response("ok", { headers: corsHeaders(origin || "null") });
  }
  if (request.method === "GET" && url.pathname.endsWith("/health")) {
    const serviceUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceUrl || !serviceKey) return json({ ok: false }, 503, origin || "null");
    const healthClient = createClient(serviceUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { error } = await healthClient.from("invoicepro_rate_limits").select("user_id").limit(1);
    return json({ ok: !error, service: "invoicepro-gateway" }, error ? 503 : 200, origin || "null");
  }
  if (origin && (!allowed.length || !allowed.includes(origin))) return json({ error: "origin_not_allowed" }, 403, origin);
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, origin || "null");
  const length = Number(request.headers.get("content-length") ?? 0);
  if (length > 32_768) return json({ error: "request_too_large" }, 413, origin || "null");

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) return json({ error: "server_not_configured" }, 503, origin || "null");
  const bearer = request.headers.get("Authorization");
  if (!bearer?.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401, origin || "null");

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: bearer } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "unauthorized" }, 401, origin || "null");

  const { data: allowedNow, error: limitError } = await adminClient.rpc("invoicepro_consume_rate_limit", {
    p_user_id: user.id,
    p_limit: 60,
    p_window_seconds: 60,
  });
  if (limitError) {
    console.error(JSON.stringify({ event: "rate_limit_check_failed", requestId: crypto.randomUUID() }));
    return json({ error: "temporarily_unavailable" }, 503, origin || "null");
  }
  if (!allowedNow) return json({ error: "rate_limited", retry_after: 60 }, 429, origin || "null");

  let input: Record<string, unknown>;
  try {
    input = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400, origin || "null");
  }
  const action = input.action;
  const requestedOffset = Number(input.offset ?? 0);
  const pageOffset = Number.isInteger(requestedOffset) ? Math.max(0, Math.min(requestedOffset, 100_000)) : 0;
  let result: { data: unknown; error: { message: string; code?: string } | null };
  switch (action) {
    case "list_documents":
      result = await userClient.from("invoicepro_documents").select("doc_key,document").eq("user_id", user.id).order("doc_key").range(pageOffset, pageOffset + 499);
      break;
    case "save_documents": {
      const documents = input.documents as Record<string, unknown>[] | undefined;
      if (!Array.isArray(documents) || documents.length > 50 || documents.some((document) => typeof document?.num !== "string" || document.num.length > 80)) return json({ error: "invalid_documents" }, 400, origin || "null");
      result = await userClient.from("invoicepro_documents").upsert(documents.map((document) => ({ user_id: user.id, doc_key: document.num, document })));
      break;
    }
    case "save_document": {
      const document = input.document as Record<string, unknown> | undefined;
      if (!document || typeof document.num !== "string" || document.num.length > 80) return json({ error: "invalid_document" }, 400, origin || "null");
      result = await userClient.from("invoicepro_documents").upsert({ user_id: user.id, doc_key: document.num, document });
      break;
    }
    case "delete_document": {
      const docKey = input.doc_key;
      if (typeof docKey !== "string" || docKey.length > 80) return json({ error: "invalid_document_key" }, 400, origin || "null");
      result = await userClient.from("invoicepro_documents").delete().eq("user_id", user.id).eq("doc_key", docKey);
      break;
    }
    case "collaborator_count":
      result = await userClient.rpc("invoicepro_collaborator_count");
      break;
    case "admin_accounts":
      result = await userClient.from("invoicepro_profiles").select("id,email,created_at", { count: "exact" }).order("created_at", { ascending: false }).range(pageOffset, pageOffset + 49);
      break;
    case "admin_account_documents": {
      const accountId = input.account_id;
      if (typeof accountId !== "string" || accountId.length > 64) return json({ error: "invalid_account_id" }, 400, origin || "null");
      result = await userClient.from("invoicepro_documents").select("document", { count: "exact" }).eq("user_id", accountId).order("doc_key").range(pageOffset, pageOffset + 49);
      break;
    }
    default:
      return json({ error: "unknown_action" }, 400, origin || "null");
  }
  if (result.error) {
    const requestId = crypto.randomUUID();
    console.error(JSON.stringify({ event: "database_request_failed", action, code: result.error.code ?? "unknown", requestId }));
    return json({ error: "request_failed", request_id: requestId }, 502, origin || "null");
  }
  return json({ data: result.data, count: "count" in result ? result.count : null }, 200, origin || "null");
});
