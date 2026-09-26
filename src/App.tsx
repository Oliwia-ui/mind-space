import "./App.css";

function App() {
  return (
    <main className="mind-space-shell">
      <div className="stars" aria-hidden="true" />
      <header className="brand-lockup">
        <span className="eyebrow">Your thoughts, still in motion</span>
        <h1>Mind Space</h1>
      </header>

      <section className="welcome-orbit" aria-label="Mind Space">
        <div className="orbit orbit-one" aria-hidden="true" />
        <div className="orbit orbit-two" aria-hidden="true" />
        <button className="sense-button" type="button">
          <span>MAKE IT</span>
          <strong>MAKE SENSE</strong>
        </button>
      </section>

      <p className="status-copy">
        Capture what is circling. Organise it when you are ready.
      </p>
    </main>
  );
}

export default App;
