// Dedicated Web Worker hosting the real Otter 1.0.1 .NET WebAssembly interpreter.
// Runs off the main UI thread so user code can never freeze the page and can be
// hard-terminated immediately via worker.terminate() when the user clicks Stop.

let exportsPromise = null;

async function ensureExports() {
  if (!exportsPromise) {
    exportsPromise = (async () => {
      const dotnetUrl = new URL('./_framework/dotnet.js', import.meta.url).href;
      const { dotnet } = await import(dotnetUrl);
      const { getAssemblyExports, getConfig } = await dotnet
        .withDiagnosticTracing(false)
        .create();
      const config = getConfig();
      const assemblyExports = await getAssemblyExports(config.mainAssemblyName);
      const api = assemblyExports.Otter.Playground.Wasm.PlaygroundExports;
      return { api, version: api.GetVersion() };
    })();
  }
  return exportsPromise;
}

self.addEventListener('message', async (event) => {
  const msg = event.data || {};
  const { id, type } = msg;
  try {
    const { api, version } = await ensureExports();
    if (type === 'init') {
      self.postMessage({ id, type: 'ready', version });
      return;
    }
    if (type === 'check') {
      const raw = api.CheckSource(String(msg.source ?? ''));
      self.postMessage({ id, type: 'result', payload: JSON.parse(raw) });
      return;
    }
    if (type === 'run') {
      const raw = api.RunSource(
        String(msg.source ?? ''),
        String(msg.stdin ?? ''),
        Number(msg.maxSteps ?? 250000),
        Number(msg.timeoutMs ?? 3000),
        Number(msg.maxOutputBytes ?? 65536)
      );
      self.postMessage({ id, type: 'result', payload: JSON.parse(raw) });
      return;
    }
    self.postMessage({ id, type: 'error', error: `Unknown worker message type: ${type}` });
  } catch (err) {
    self.postMessage({
      id,
      type: 'error',
      error: err && err.message ? err.message : String(err)
    });
  }
});
