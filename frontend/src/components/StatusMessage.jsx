function StatusMessage({ message, error }) {
  if (!message && !error) {
    return null;
  }

  return (
    <div className="status-messages">
      {message ? <div className="status success">{message}</div> : null}
      {error ? <div className="status error">{error}</div> : null}
    </div>
  );
}

export default StatusMessage;
