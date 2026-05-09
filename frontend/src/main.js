import React, { useEffect, useMemo, useState } from "https://esm.sh/react@18.3.1";
import { createRoot } from "https://esm.sh/react-dom@18.3.1/client";
import htm from "https://esm.sh/htm@3.1.1";

const html = htm.bind(React.createElement);
const API_ROOT = "/api";

const ICONS = {
  camera: html`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h3l1.5-2h7L17 7h3a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2Zm8 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z" fill="currentColor"></path></svg>`,
  play: html`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z" fill="currentColor"></path></svg>`,
  stop: html`<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="1.5" fill="currentColor"></rect></svg>`,
  trash: html`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 3h6l1 2h4v2H4V5h4l1-2Zm1 7h2v8h-2v-8Zm4 0h2v8h-2v-8ZM6 7h12l-1 13a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2L6 7Z" fill="currentColor"></path></svg>`,
  signal: html`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 18h2v2H4v-2Zm4-4h2v6H8v-6Zm4-4h2v10h-2V10Zm4-4h2v14h-2V6Z" fill="currentColor"></path></svg>`,
  person: html`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-7 9a7 7 0 1 1 14 0H5Z" fill="currentColor"></path></svg>`,
  chip: html`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 2h6v3h2.5V2H19v3.5H22v3h-3v2.5h3v2.5h-3V16h3v3h-3V22h-1.5v-3H15v3H9v-3H6.5v3H5v-3H2v-3h3V13.5H2V11h3V8.5H2v-3h3V2h1.5v3H9V2Zm-2 6v8h10V8H7Z" fill="currentColor"></path></svg>`,
  box: html`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 2 8 4v12l-8 4-8-4V6l8-4Zm0 2.2L6.5 7 12 9.8 17.5 7 12 4.2Zm-6 4.5v8l5 2.5v-8L6 8.7Zm7 10.5 5-2.5v-8l-5 2.5v8Z" fill="currentColor"></path></svg>`,
  bolt: html`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z" fill="currentColor"></path></svg>`,
};

function wsUrl(path) {
  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  return `${protocol}://${window.location.host}${path}`;
}

async function api(path, options = {}) {
  const response = await fetch(`${API_ROOT}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.detail || "Request failed");
  }
  return payload.payload;
}

function formatTimestamp(timestamp) {
  if (!timestamp) {
    return "No signal";
  }
  return new Date(timestamp * 1000).toLocaleString();
}

function timeAgo(timestamp) {
  if (!timestamp) {
    return "Never";
  }
  const delta = Math.max(0, Math.round(Date.now() / 1000 - timestamp));
  if (delta < 5) return "Just now";
  if (delta < 60) return `${delta}s ago`;
  if (delta < 3600) return `${Math.floor(delta / 60)}m ago`;
  return `${Math.floor(delta / 3600)}h ago`;
}

function aggregateClassCounts(sources) {
  const counts = {};
  for (const source of sources) {
    for (const [className, value] of Object.entries(source.counts_by_class || {})) {
      counts[className] = (counts[className] || 0) + value;
    }
  }
  return Object.entries(counts).sort((left, right) => right[1] - left[1]);
}

function MetricChip({ icon, label, value, tone = "neutral" }) {
  return html`
    <div className=${`metric-chip metric-chip--${tone}`}>
      <span className="metric-chip__icon">${icon}</span>
      <span className="metric-chip__meta">
        <span className="metric-chip__label">${label}</span>
        <strong className="metric-chip__value">${value}</strong>
      </span>
    </div>
  `;
}

function IconButton({ icon, label, tone = "neutral", disabled = false, onClick }) {
  return html`
    <button className=${`icon-button icon-button--${tone}`} disabled=${disabled} onClick=${onClick}>
      <span className="icon-button__icon">${icon}</span>
      <span>${label}</span>
    </button>
  `;
}

function SourceCard({ source, onStart, onStop, onDelete }) {
  const preview = source.preview_jpeg_base64
    ? `data:image/jpeg;base64,${source.preview_jpeg_base64}`
    : null;
  const statusTone =
    source.status === "running"
      ? "good"
      : source.status === "error"
      ? "danger"
      : source.status === "reconnecting"
      ? "warning"
      : "neutral";

  return html`
    <article className="source-card">
      <header className="source-card__header">
        <div>
          <h3>${source.name}</h3>
          <p>${source.source_type}${source.camera_index !== null ? `:${source.camera_index}` : ""}</p>
        </div>
        <span className=${`pill pill--${statusTone}`}>${source.status}</span>
      </header>

      <div className="source-card__preview">
        ${
          preview
            ? html`<img src=${preview} alt=${`${source.name} preview`} />`
            : html`
                <div className="source-card__placeholder">
                  <span>${ICONS.camera}</span>
                  <strong>No frame</strong>
                </div>
              `
        }
      </div>

      <div className="source-card__toolbar">
        <${IconButton} icon=${ICONS.play} label="Start" tone="good" disabled=${source.status === "running"} onClick=${() => onStart(source.source_id)} />
        <${IconButton} icon=${ICONS.stop} label="Stop" tone="warning" disabled=${source.status !== "running" && source.status !== "reconnecting"} onClick=${() => onStop(source.source_id)} />
        <${IconButton} icon=${ICONS.trash} label="Delete" tone="danger" onClick=${() => onDelete(source.source_id)} />
      </div>

      <dl className="source-card__stats">
        <div>
          <dt>FPS</dt>
          <dd>${source.fps || 0}</dd>
        </div>
        <div>
          <dt>Objects</dt>
          <dd>${(source.objects || []).length}</dd>
        </div>
        <div>
          <dt>Last frame</dt>
          <dd>${timeAgo(source.last_frame_at)}</dd>
        </div>
      </dl>

      ${
        source.last_error
          ? html`<p className="source-card__error">${source.last_error}</p>`
          : null
      }

      <div className="source-card__list">
        <div className="source-card__list-head">
          <span>Tracked objects</span>
          <span>${(source.objects || []).length}</span>
        </div>
        ${
          (source.objects || []).length
            ? source.objects.map(
                (item) => html`
                  <div className="object-row" key=${`${source.source_id}-${item.identity_id}-${item.tracker_id}`}>
                    <div>
                      <strong>${item.label}</strong>
                      <p>${item.semantic_label || item.class_name}</p>
                    </div>
                    <div className="object-row__meta">
                      <span>${Math.round((item.confidence || 0) * 100)}%</span>
                      ${item.reacquired ? html`<span className="pill pill--good">re-id</span>` : null}
                    </div>
                  </div>
                `
              )
            : html`<div className="empty-state">No confirmed tracks</div>`
        }
      </div>
    </article>
  `;
}

function SourceForm({ value, busy, onChange, onSubmit }) {
  return html`
    <form className="source-form" onSubmit=${onSubmit}>
      <div className="form-row">
        <label>
          <span>Name</span>
          <input name="name" value=${value.name} onInput=${onChange} placeholder="Front dock camera" required />
        </label>
        <label>
          <span>Type</span>
          <select name="source_type" value=${value.source_type} onChange=${onChange}>
            <option value="camera">camera</option>
            <option value="rtsp">rtsp</option>
            <option value="http">http</option>
            <option value="file">file</option>
          </select>
        </label>
      </div>

      <div className="form-row">
        ${
          value.source_type === "camera"
            ? html`
                <label>
                  <span>Camera index</span>
                  <input name="camera_index" type="number" min="0" value=${value.camera_index} onInput=${onChange} />
                </label>
              `
            : html`
                <label className="grow">
                  <span>URI or path</span>
                  <input name="uri" value=${value.uri} onInput=${onChange} placeholder="rtsp://user:pass@host/stream" required />
                </label>
              `
        }
        <label>
          <span>Target FPS</span>
          <input name="target_fps" type="number" min="1" max="30" value=${value.target_fps} onInput=${onChange} />
        </label>
      </div>

      <div className="form-row">
        <label className="grow">
          <span>Class filter</span>
          <input
            name="enabled_classes"
            value=${value.enabled_classes}
            onInput=${onChange}
            placeholder="person, car, truck"
          />
        </label>
        <label className="toggle">
          <span>Auto-start</span>
          <input name="auto_start" type="checkbox" checked=${value.auto_start} onChange=${onChange} />
        </label>
      </div>

      <div className="form-actions">
        <button className="primary-button" type="submit" disabled=${busy}>
          <span>${ICONS.camera}</span>
          <span>${busy ? "Attaching..." : "Attach source"}</span>
        </button>
      </div>
    </form>
  `;
}

function RuntimePanel({ runtime, modelConfig }) {
  const dependencies = runtime?.dependencies || [];
  return html`
    <section className="panel">
      <div className="panel__header">
        <h2>Runtime</h2>
      </div>
      <div className="runtime-grid">
        ${dependencies.map(
          (dependency) => html`
            <div className="runtime-row" key=${dependency.module}>
              <div>
                <strong>${dependency.package}</strong>
                <p>${dependency.feature}</p>
              </div>
              <span className=${`pill pill--${dependency.available ? "good" : "danger"}`}>
                ${dependency.available ? dependency.version || "ready" : "missing"}
              </span>
            </div>
          `
        )}
      </div>
      <div className="runtime-models">
        <div><span>Detector</span><strong>${modelConfig?.detector_model || "-"}</strong></div>
        <div><span>Embeddings</span><strong>${modelConfig?.clip_model || "-"}</strong></div>
        <div><span>Labeler</span><strong>${modelConfig?.vlm_enabled ? modelConfig?.vlm_model : "disabled"}</strong></div>
      </div>
    </section>
  `;
}

function IdentityPanel({ identities }) {
  return html`
    <section className="panel">
      <div className="panel__header">
        <h2>Identity ledger</h2>
      </div>
      <div className="identity-table">
        <div className="identity-table__head">
          <span>Label</span>
          <span>Class</span>
          <span>Source</span>
          <span>Seen</span>
        </div>
        ${
          identities.length
            ? identities.map(
                (identity) => html`
                  <div className="identity-table__row" key=${identity.global_id}>
                    <strong>${identity.label}</strong>
                    <span>${identity.semantic_label || identity.class_name}</span>
                    <span>${identity.primary_source_id}</span>
                    <span>${timeAgo(identity.last_seen_at)}</span>
                  </div>
                `
              )
            : html`<div className="empty-state">No identities registered</div>`
        }
      </div>
    </section>
  `;
}

function EventPanel({ events }) {
  return html`
    <section className="panel">
      <div className="panel__header">
        <h2>Recent events</h2>
      </div>
      <div className="event-list">
        ${
          events.length
            ? events.map(
                (event, index) => html`
                  <div className="event-row" key=${`${event.identity_id || "event"}-${index}`}>
                    <div>
                      <strong>${event.label || event.identity_id || "event"}</strong>
                      <p>${event.type} on ${event.source_id}</p>
                    </div>
                    <span>${timeAgo(event.ts)}</span>
                  </div>
                `
              )
            : html`<div className="empty-state">No transitions captured</div>`
        }
      </div>
    </section>
  `;
}

function ClassBreakdown({ classCounts }) {
  const maxValue = classCounts.length ? classCounts[0][1] : 1;
  return html`
    <section className="panel">
      <div className="panel__header">
        <h2>Class pressure</h2>
      </div>
      <div className="class-breakdown">
        ${
          classCounts.length
            ? classCounts.map(
                ([label, value]) => html`
                  <div className="class-breakdown__row" key=${label}>
                    <div className="class-breakdown__meta">
                      <strong>${label}</strong>
                      <span>${value}</span>
                    </div>
                    <div className="class-breakdown__bar">
                      <span style=${{ width: `${Math.max((value / maxValue) * 100, 8)}%` }}></span>
                    </div>
                  </div>
                `
              )
            : html`<div className="empty-state">No class counts yet</div>`
        }
      </div>
    </section>
  `;
}

function App() {
  const [dashboard, setDashboard] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({
    name: "",
    source_type: "camera",
    camera_index: 0,
    uri: "",
    target_fps: 4,
    enabled_classes: "",
    auto_start: true,
  });

  useEffect(() => {
    let socket;
    let reconnectTimer;

    const load = async () => {
      try {
        const payload = await api("/dashboard");
        setDashboard(payload);
        setError("");
      } catch (fetchError) {
        setError(fetchError.message);
      }
    };

    const connect = () => {
      socket = new WebSocket(wsUrl("/ws/dashboard"));
      socket.onmessage = (event) => {
        setDashboard(JSON.parse(event.data));
        setError("");
      };
      socket.onerror = () => {
        setError("WebSocket stream unavailable; polling API");
      };
      socket.onclose = () => {
        reconnectTimer = window.setTimeout(connect, 3000);
      };
    };

    load();
    connect();
    return () => {
      if (socket) socket.close();
      if (reconnectTimer) window.clearTimeout(reconnectTimer);
    };
  }, []);

  const classCounts = useMemo(() => aggregateClassCounts(dashboard?.sources || []), [dashboard]);
  const summary = dashboard?.summary || {};
  const identities = dashboard?.identities || [];
  const recentEvents = dashboard?.recent_events || [];

  const refreshDashboard = async () => {
    const payload = await api("/dashboard");
    setDashboard(payload);
  };

  const handleChange = (event) => {
    const { name, type, value, checked } = event.target;
    setForm((current) => ({
      ...current,
      [name]: type === "checkbox" ? checked : value,
    }));
  };

  const handleSubmit = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      const payload = {
        name: form.name,
        source_type: form.source_type,
        target_fps: Number(form.target_fps),
        enabled_classes: form.enabled_classes
          .split(",")
          .map((value) => value.trim())
          .filter(Boolean),
        auto_start: Boolean(form.auto_start),
      };
      if (form.source_type === "camera") {
        payload.camera_index = Number(form.camera_index || 0);
      } else {
        payload.uri = form.uri;
      }
      await api("/sources", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      setForm({
        name: "",
        source_type: "camera",
        camera_index: 0,
        uri: "",
        target_fps: 4,
        enabled_classes: "",
        auto_start: true,
      });
      await refreshDashboard();
    } catch (submitError) {
      setError(submitError.message);
    } finally {
      setBusy(false);
    }
  };

  const invokeSourceAction = async (sourceId, action, method = "POST") => {
    setError("");
    try {
      await api(`/sources/${sourceId}${action ? `/${action}` : ""}`, { method });
      await refreshDashboard();
    } catch (actionError) {
      setError(actionError.message);
    }
  };

  return html`
    <div className="app-shell">
      <header className="topbar">
        <div className="topbar__identity">
          <p>vision control plane</p>
          <h1>${dashboard?.app_name || "Sentinel Vision Console"}</h1>
          <span>Last update: ${formatTimestamp(dashboard?.generated_at)}</span>
        </div>
        <div className="topbar__metrics">
          <${MetricChip} icon=${ICONS.signal} label="Active sources" value=${summary.active_sources || 0} tone="good" />
          <${MetricChip} icon=${ICONS.person} label="Active identities" value=${summary.active_identities || 0} tone="accent" />
          <${MetricChip} icon=${ICONS.box} label="Tracked objects" value=${summary.tracked_objects || 0} tone="warning" />
          <${MetricChip} icon=${ICONS.chip} label="QLoRA labeler" value=${dashboard?.model_config?.vlm_enabled ? "armed" : "standby"} tone="neutral" />
        </div>
      </header>

      ${error ? html`<div className="banner banner--error">${error}</div>` : null}

      <main className="workspace">
        <section className="workspace__band workspace__band--split">
          <div className="panel panel--form">
            <div className="panel__header">
              <h2>Attach source</h2>
            </div>
            <${SourceForm} value=${form} busy=${busy} onChange=${handleChange} onSubmit=${handleSubmit} />
          </div>
          <${RuntimePanel} runtime=${dashboard?.runtime} modelConfig=${dashboard?.model_config} />
        </section>

        <section className="workspace__band workspace__band--content">
          <div className="feed-region">
            <div className="panel-header-inline">
              <h2>Feeds</h2>
              <span>${(dashboard?.sources || []).length} configured</span>
            </div>
            <div className="feed-grid">
              ${
                (dashboard?.sources || []).length
                  ? dashboard.sources.map(
                      (source) => html`
                        <${SourceCard}
                          key=${source.source_id}
                          source=${source}
                          onStart=${(sourceId) => invokeSourceAction(sourceId, "start")}
                          onStop=${(sourceId) => invokeSourceAction(sourceId, "stop")}
                          onDelete=${(sourceId) => invokeSourceAction(sourceId, "", "DELETE")}
                        />
                      `
                    )
                  : html`
                      <div className="empty-feed-state">
                        <span>${ICONS.camera}</span>
                        <strong>No active feeds</strong>
                      </div>
                    `
              }
            </div>
          </div>

          <aside className="side-rail">
            <${ClassBreakdown} classCounts=${classCounts} />
            <${IdentityPanel} identities=${identities} />
            <${EventPanel} events=${recentEvents} />
          </aside>
        </section>
      </main>
    </div>
  `;
}

createRoot(document.getElementById("root")).render(html`<${App} />`);

