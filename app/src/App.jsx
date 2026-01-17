import { useEffect, useMemo, useState } from "react";

function getSavedToken() {
  return localStorage.getItem("accessToken") || "";
}

export default function App() {
  const [config, setConfig] = useState(null);
  const [configErr, setConfigErr] = useState("");

  const [accessToken, setAccessToken] = useState(getSavedToken());
  const [notes, setNotes] = useState([]);
  const [text, setText] = useState("");
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState("");

  // ✅ remove spaces + newlines from pasted token
  const cleanToken = useMemo(() => (accessToken || "").replace(/\s+/g, ""), [accessToken]);

  const headers = useMemo(() => {
    const h = { "Content-Type": "application/json" };
    if (cleanToken) h.Authorization = `Bearer ${cleanToken}`;
    return h;
  }, [cleanToken]);

  // Load runtime config from the same site (CloudFront)
  async function loadConfig() {
    setConfigErr("");
    try {
      const res = await fetch("/config.json", { cache: "no-store" });
      if (!res.ok) throw new Error(`config.json fetch failed (${res.status})`);
      const data = await res.json();

      if (!data?.apiBase) throw new Error("config.json missing apiBase");
      setConfig(data);
    } catch (e) {
      setConfigErr(e?.message || String(e));
    }
  }

  async function fetchNotes() {
    if (!config?.apiBase) return;
    setErr("");
    setLoading(true);
    try {
      const res = await fetch(`${config.apiBase}/notes`, { headers });
      if (!res.ok) {
        const body = await res.text();
        throw new Error(`GET /notes failed (${res.status}): ${body}`);
      }
      const data = await res.json();
      setNotes(Array.isArray(data.items) ? data.items : []);
    } catch (e) {
      setErr(e?.message || String(e));
    } finally {
      setLoading(false);
    }
  }

  async function createNote(e) {
    e.preventDefault();
    if (!config?.apiBase) return;
    setErr("");
    if (!text.trim()) return;

    setLoading(true);
    try {
      const res = await fetch(`${config.apiBase}/notes`, {
        method: "POST",
        headers,
        body: JSON.stringify({ text }),
      });

      if (!res.ok) {
        const body = await res.text();
        throw new Error(`POST /notes failed (${res.status}): ${body}`);
      }

      setText("");
      await fetchNotes();
    } catch (e) {
      setErr(e?.message || String(e));
    } finally {
      setLoading(false);
    }
  }

  async function deleteNote(noteId) {
    if (!config?.apiBase) return;
    setErr("");
    setLoading(true);
    try {
      const res = await fetch(`${config.apiBase}/notes/${encodeURIComponent(noteId)}`, {
        method: "DELETE",
        headers,
      });

      if (!res.ok) {
        const body = await res.text();
        throw new Error(`DELETE /notes/${noteId} failed (${res.status}): ${body}`);
      }

      await fetchNotes();
    } catch (e) {
      setErr(e?.message || String(e));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadConfig();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function saveToken() {
    const cleaned = (accessToken || "").replace(/\s+/g, "");
    localStorage.setItem("accessToken", cleaned);
    setAccessToken(cleaned);
    if (config?.apiBase) fetchNotes();
  }

  function clearToken() {
    localStorage.removeItem("accessToken");
    setAccessToken("");
    setNotes([]);
  }

  const ready = !!config?.apiBase;

  return (
    <div style={{ maxWidth: 760, margin: "40px auto", padding: 16, fontFamily: "system-ui" }}>
      <h1>DLAGROUP Notes</h1>
      <p style={{ opacity: 0.8 }}>Phase 1: React → API Gateway → Lambda → DynamoDB</p>

      {!ready && (
        <div style={{ border: "1px solid #333", borderRadius: 10, padding: 12, marginBottom: 16 }}>
          <b>Loading config…</b>
          <div style={{ opacity: 0.8, marginTop: 8 }}>
            Trying to fetch <code>/config.json</code>
          </div>
          {configErr && (
            <div style={{ marginTop: 10, background: "#3a0f0f", padding: 10, borderRadius: 10 }}>
              <b>Config error:</b> {configErr}
              <div style={{ marginTop: 8, opacity: 0.8 }}>
                Make sure <code>config.json</code> exists in your S3 site bucket and CloudFront invalidation completed.
              </div>
            </div>
          )}
        </div>
      )}

      {ready && (
        <div style={{ border: "1px solid #333", borderRadius: 10, padding: 12, marginBottom: 16 }}>
          <div style={{ opacity: 0.8, marginBottom: 6 }}>
            API Base from config: <code>{config.apiBase}</code>
          </div>
          <div style={{ opacity: 0.8 }}>
            Region: <code>{config.region}</code> • UserPool: <code>{config.userPoolId}</code> • ClientId:{" "}
            <code>{config.clientId}</code>
          </div>
        </div>
      )}

      <div style={{ border: "1px solid #333", borderRadius: 10, padding: 12, marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Access Token (temporary for Phase 1)</h3>
        <p style={{ marginTop: 0, opacity: 0.8 }}>
          Paste your Cognito <b>AccessToken</b> here. Phase 2 will replace this with real login.
        </p>

        <textarea
          value={accessToken}
          onChange={(e) => setAccessToken(e.target.value)}
          rows={4}
          style={{ width: "100%", padding: 10 }}
          placeholder="Paste AccessToken here..."
        />

        <div style={{ display: "flex", gap: 8, marginTop: 10, flexWrap: "wrap" }}>
          <button onClick={saveToken} disabled={!accessToken.trim() || loading || !ready}>
            Save token + Load notes
          </button>
          <button onClick={clearToken} disabled={loading}>
            Clear token
          </button>
          <button onClick={fetchNotes} disabled={!cleanToken || loading || !ready}>
            Refresh
          </button>
          <button onClick={loadConfig} disabled={loading}>
            Reload config
          </button>
        </div>
      </div>

      {err && (
        <div style={{ background: "#3a0f0f", padding: 12, borderRadius: 10, marginBottom: 16 }}>
          <b>Error:</b> {err}
        </div>
      )}

      <form onSubmit={createNote} style={{ display: "flex", gap: 8, marginBottom: 16 }}>
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Write a note..."
          style={{ flex: 1, padding: 10 }}
        />
        <button type="submit" disabled={!cleanToken || loading || !ready}>
          Add
        </button>
      </form>

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2 style={{ margin: 0 }}>Notes</h2>
        {loading && <span style={{ opacity: 0.7 }}>Loading…</span>}
      </div>

      <ul style={{ paddingLeft: 18 }}>
        {notes.map((n) => (
          <li key={n.noteId} style={{ margin: "10px 0" }}>
            <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
              <div style={{ flex: 1 }}>
                <div>
                  <b>{n.text}</b>
                </div>
                <div style={{ opacity: 0.7, fontSize: 12 }}>
                  {n.noteId} • {n.createdAt}
                </div>
              </div>
              <button onClick={() => deleteNote(n.noteId)} disabled={loading}>
                Delete
              </button>
            </div>
          </li>
        ))}
      </ul>

      {!cleanToken && <p style={{ opacity: 0.75 }}>Add your AccessToken above to load notes.</p>}
    </div>
  );
}
