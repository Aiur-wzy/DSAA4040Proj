import { useCallback, useEffect, useMemo, useState } from "react";
import { getClusterStatus } from "../api";

const REFRESH_MS = 5000;
const MAX_SAMPLES = 60;

function formatValue(value, fallback = "—") {
  return value === null || value === undefined ? fallback : value;
}

function formatTime(value) {
  if (!value) {
    return "—";
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleTimeString();
}

function scalingState(status) {
  const hpa = status?.hpa || {};
  const cpu = hpa.currentCPUUtilization;
  const target = hpa.targetCPUUtilization;
  const desired = hpa.desiredReplicas;
  const current = hpa.currentReplicas;

  if (!status?.metricsAvailable) {
    return "Metrics unavailable";
  }
  if (desired && hpa.maxReplicas && desired >= hpa.maxReplicas) {
    return "At max replicas";
  }
  if (desired && current && desired > current) {
    return "Scaling up";
  }
  if (cpu !== null && cpu !== undefined && target && cpu > target) {
    return "High CPU";
  }
  return "Idle";
}

function sampleFromStatus(status) {
  const now = new Date();
  return {
    timestamp: now.toISOString(),
    label: now.toLocaleTimeString(),
    desiredReplicas: status?.deployment?.desiredReplicas ?? null,
    readyReplicas: status?.deployment?.readyReplicas ?? null,
    hpaCurrentReplicas: status?.hpa?.currentReplicas ?? null,
    hpaDesiredReplicas: status?.hpa?.desiredReplicas ?? null,
    cpu: status?.hpa?.currentCPUUtilization ?? null,
    cpuTarget: status?.hpa?.targetCPUUtilization ?? null,
    metricsAvailable: Boolean(status?.metricsAvailable)
  };
}

function pointsForLine(samples, field, width, height, padding, maxValue) {
  const drawableWidth = width - padding * 2;
  const drawableHeight = height - padding * 2;
  const denom = Math.max(samples.length - 1, 1);
  return samples
    .map((sample, index) => {
      const value = sample[field];
      if (value === null || value === undefined) {
        return null;
      }
      const x = padding + (index / denom) * drawableWidth;
      const y = height - padding - (Number(value) / maxValue) * drawableHeight;
      return `${x},${y}`;
    })
    .filter(Boolean)
    .join(" ");
}

function SimpleLineChart({ title, samples, lines, emptyMessage }) {
  const width = 640;
  const height = 220;
  const padding = 32;
  const values = samples.flatMap((sample) =>
    lines.map((line) => sample[line.field]).filter((value) => value !== null && value !== undefined)
  );
  const maxLineValue = lines.reduce((max, line) => Math.max(max, line.referenceValue || 0), 0);
  const maxValue = Math.max(1, Math.ceil(Math.max(maxLineValue, ...values, 0) * 1.2));
  const hasData = values.length > 0;

  return (
    <section className="panel monitoring-chart">
      <h3>{title}</h3>
      {!hasData ? (
        <p className="muted">{emptyMessage}</p>
      ) : (
        <>
          <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={title}>
            <line x1={padding} y1={padding} x2={padding} y2={height - padding} className="chart-axis" />
            <line x1={padding} y1={height - padding} x2={width - padding} y2={height - padding} className="chart-axis" />
            <text x={padding} y={padding - 10} className="chart-label">{maxValue}</text>
            <text x={padding} y={height - 8} className="chart-label">0</text>
            {lines.map((line) => (
              <polyline
                key={line.field}
                points={pointsForLine(samples, line.field, width, height, padding, maxValue)}
                className={`chart-line ${line.className}`}
              />
            ))}
          </svg>
          <div className="chart-legend">
            {lines.map((line) => (
              <span key={line.field}>
                <span className={`legend-swatch ${line.className}`} /> {line.label}
              </span>
            ))}
          </div>
          <p className="muted chart-window">
            Showing up to {MAX_SAMPLES} browser-memory samples. Latest sample: {samples.at(-1)?.label || "—"}
          </p>
        </>
      )}
    </section>
  );
}

function MetricCard({ title, children }) {
  return (
    <section className="panel monitoring-card">
      <h3>{title}</h3>
      {children}
    </section>
  );
}

function MonitoringDashboard({ onBack }) {
  const [status, setStatus] = useState(null);
  const [samples, setSamples] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const refreshStatus = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const result = await getClusterStatus();
      setStatus(result);
      setSamples((current) => [...current, sampleFromStatus(result)].slice(-MAX_SAMPLES));
    } catch (err) {
      setError(`Failed to load cluster status: ${err.message}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refreshStatus();
    const timer = window.setInterval(refreshStatus, REFRESH_MS);
    return () => window.clearInterval(timer);
  }, [refreshStatus]);

  const hpaState = useMemo(() => scalingState(status), [status]);
  const deployment = status?.deployment || {};
  const hpa = status?.hpa || {};
  const pods = status?.pods || [];
  const warnings = status?.warnings || [];
  const hasClusterError = Boolean(status?.error || error);

  return (
    <div className="monitoring-page">
      <header className="monitoring-header">
        <div>
          <h1>Monitoring / HPA Dashboard</h1>
          <p className="muted">
            Read-only Kubernetes status for the public-backend Deployment, HPA, and Pods. Auto-refreshes every 5 seconds.
          </p>
        </div>
        <div className="header-actions">
          <button type="button" onClick={refreshStatus} disabled={loading}>
            {loading ? "Refreshing..." : "Refresh"}
          </button>
          <button type="button" onClick={onBack}>Back to Store</button>
        </div>
      </header>

      {error ? <div className="status error">{error}</div> : null}
      {hasClusterError ? (
        <div className="status error">
          Cluster status is only available when the backend is running inside Kubernetes with the required RBAC permissions.
        </div>
      ) : null}
      {status && !status.metricsAvailable ? (
        <div className="status warning">
          Metrics are unavailable. Run ./scripts/k8s-fix-metrics-server.sh and check kubectl top pods.
        </div>
      ) : null}
      {warnings.map((warning) => (
        <div className="status warning" key={warning}>{warning}</div>
      ))}

      <div className="monitoring-cards">
        <MetricCard title="public-backend Deployment">
          <dl className="metric-grid">
            <dt>Name</dt><dd>{formatValue(deployment.name)}</dd>
            <dt>Desired replicas</dt><dd>{formatValue(deployment.desiredReplicas)}</dd>
            <dt>Ready replicas</dt><dd>{formatValue(deployment.readyReplicas)}</dd>
            <dt>Available replicas</dt><dd>{formatValue(deployment.availableReplicas)}</dd>
            <dt>Updated replicas</dt><dd>{formatValue(deployment.updatedReplicas)}</dd>
          </dl>
        </MetricCard>

        <MetricCard title="HPA">
          <dl className="metric-grid">
            <dt>Name</dt><dd>{formatValue(hpa.name)}</dd>
            <dt>CPU utilization</dt>
            <dd>{formatValue(hpa.currentCPUUtilization)}% / {formatValue(hpa.targetCPUUtilization)}%</dd>
            <dt>Min / max replicas</dt><dd>{formatValue(hpa.minReplicas)} / {formatValue(hpa.maxReplicas)}</dd>
            <dt>Current / desired</dt><dd>{formatValue(hpa.currentReplicas)} / {formatValue(hpa.desiredReplicas)}</dd>
            <dt>Scaling state</dt><dd><strong>{hpaState}</strong></dd>
          </dl>
        </MetricCard>
      </div>

      <div className="monitoring-charts">
        <SimpleLineChart
          title="public-backend Replicas Over Time"
          samples={samples}
          emptyMessage="Replica samples will appear after the first successful refresh."
          lines={[
            { field: "desiredReplicas", label: "Deployment desired", className: "line-blue" },
            { field: "readyReplicas", label: "Deployment ready", className: "line-green" },
            { field: "hpaDesiredReplicas", label: "HPA desired", className: "line-orange" }
          ]}
        />
        <SimpleLineChart
          title="HPA CPU Utilization Over Time"
          samples={samples.filter((sample) => sample.metricsAvailable)}
          emptyMessage="CPU metrics are unavailable. Run ./scripts/k8s-fix-metrics-server.sh and verify kubectl top pods."
          lines={[
            { field: "cpu", label: "Current CPU %", className: "line-red" },
            { field: "cpuTarget", label: "Target CPU %", className: "line-gray", referenceValue: hpa.targetCPUUtilization || 50 }
          ]}
        />
      </div>

      <section className="panel">
        <h2>public-backend Pods</h2>
        <div className="table-wrap">
          <table className="pods-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Phase</th>
                <th>Ready</th>
                <th>Restarts</th>
                <th>CPU</th>
                <th>Memory</th>
                <th>Start time</th>
              </tr>
            </thead>
            <tbody>
              {pods.map((pod) => (
                <tr key={pod.name}>
                  <td>{pod.name}</td>
                  <td>{pod.phase}</td>
                  <td>{pod.ready ? "Yes" : "No"}</td>
                  <td>{pod.restartCount}</td>
                  <td>{formatValue(pod.cpu)}</td>
                  <td>{formatValue(pod.memory)}</td>
                  <td>{formatTime(pod.startTime)}</td>
                </tr>
              ))}
              {!pods.length ? (
                <tr>
                  <td colSpan="7" className="muted">No public-backend Pods reported yet.</td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

export default MonitoringDashboard;
