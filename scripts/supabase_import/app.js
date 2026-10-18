'use strict';
const config = JSON.parse(document.getElementById('config').textContent);
const button = document.getElementById('start');
const progress = document.getElementById('progress');
const state = document.getElementById('state');
const details = document.getElementById('details');
const format = n => new Intl.NumberFormat('pt-BR').format(n);

function done() {
  progress.value = 100;
  state.className = 'success';
  state.textContent = 'ELF recebido e SHA-256 confirmado no workspace.';
  details.textContent = `${format(config.bytes)} bytes · SHA-256\n${config.sha256}\n\nO próximo passo é a análise integral pelo agente. Ainda não é um jogo nativo executável.`;
  button.textContent = 'Cópia local validada';
  button.disabled = true;
  monitorAnalysis();
}

async function monitorAnalysis() {
  const output = document.getElementById('analysis');
  try {
    const response = await fetch('/api/status', {cache: 'no-store'});
    if (!response.ok) throw new Error('Consulta indisponível.');
    const {analysis} = await response.json();
    if (!analysis || !analysis.enabled) return;
    if (analysis.state === 'completed') {
      output.textContent = 'A primeira execução de FASE 1 terminou. O agente ainda precisa validar os resultados; isto não é um executável Windows.';
    } else if (analysis.state === 'failed') {
      output.textContent = `ELF preservado e validado. A análise retornou erro (código ${analysis.exit_code ?? 'de inicialização'}); o log está disponível para o agente investigar.`;
    } else {
      output.textContent = analysis.state === 'running'
        ? 'Análise integral em execução: Ghidra → comparação dos mapas → tentativa de C++. Pode levar vários minutos.'
        : 'Análise integral programada para iniciar automaticamente após a cópia validada.';
      setTimeout(monitorAnalysis, 3000);
    }
  } catch (_) {
    output.textContent = 'ELF já verificado. Não foi possível consultar o andamento da análise agora.';
  }
}

async function begin() {
  button.disabled = true;
  state.className = '';
  details.textContent = '';
  try {
    progress.value = 0;
    state.textContent = 'Buscando o ELF no seu Supabase…';
    // Public object only. Do not send preview cookies, nonce or cloud keys here.
    const response = await fetch(config.source_url, {
      mode: 'cors', credentials: 'omit', cache: 'no-store', redirect: 'error'
    });
    if (!response.ok) throw new Error(`Supabase respondeu HTTP ${response.status}.`);
    const reader = response.body.getReader();
    const chunks = [];
    let received = 0;
    while (true) {
      const {value, done: ended} = await reader.read();
      if (ended) break;
      received += value.length;
      if (received > config.bytes) {
        await reader.cancel();
        throw new Error('O objeto excede o tamanho esperado. Transferência recusada.');
      }
      chunks.push(value);
      progress.value = 60 * received / config.bytes;
      details.textContent = `${format(received)} / ${format(config.bytes)} bytes recebidos do Supabase.`;
    }
    if (received !== config.bytes) throw new Error(`Tamanho incorreto: ${received} bytes.`);
    const bytes = new Uint8Array(received);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    state.textContent = 'Conferindo a identidade do arquivo no navegador…';
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    const hash = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
    if (hash !== config.sha256) throw new Error('SHA-256 diferente do ELF americano registrado. Nada será importado.');
    progress.value = 70;
    state.textContent = 'Entregando ao workspace para nova verificação independente…';
    // Relative endpoint: normal authenticated preview access, never localhost.
    const uploaded = await fetch('/api/import', {
      method: 'POST', credentials: 'same-origin', redirect: 'error',
      headers: {'Content-Type': 'application/octet-stream', 'X-Import-Nonce': config.nonce},
      body: bytes
    });
    const result = await uploaded.json();
    if (!uploaded.ok || !result.verified || result.bytes !== config.bytes || result.sha256 !== config.sha256)
      throw new Error(result.error || 'O workspace não confirmou a cópia.');
    done();
  } catch (error) {
    state.className = 'error';
    state.textContent = 'Transferência não concluída.';
    details.textContent = `${error.message}\n\nO original não foi alterado. Se a conexão foi bloqueada, informe ao agente a mensagem acima; não é necessário anexar o arquivo.`;
    button.disabled = false;
    button.textContent = 'Tentar buscar novamente';
  }
}

button.addEventListener('click', begin);
(async () => {
  try {
    const response = await fetch('/api/status', {cache: 'no-store'});
    if (!response.ok) throw new Error(`Workspace respondeu HTTP ${response.status}.`);
    const status = await response.json();
    if (status.verified) { done(); return; }
    button.textContent = 'Buscar do meu Supabase';
    button.disabled = false;
    state.textContent = 'Pronto. Toque no botão para buscar o arquivo.';
    details.textContent = 'Origem fixa: Supabase do proprietário. Sem senha e sem seletor de anexos.';
    if (new URLSearchParams(location.search).get('auto') === '1') await begin();
  } catch (error) {
    state.className = 'error';
    state.textContent = 'Não foi possível consultar o workspace.';
    details.textContent = error.message;
  }
})();
