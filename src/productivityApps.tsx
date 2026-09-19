import { useEffect, useRef, useState } from 'react';
import { ApplicationRegistry, type AppId } from './windowManager';

type AppApi = { launch: (id: AppId, args?: unknown) => void };
type AppArgs = { path?: string; content?: string; url?: string } | undefined;

function Notepad({ args }: { args: AppArgs }) {
  const [text, setText] = useState(args?.content ?? '');
  const [saved, setSaved] = useState(true);
  const path = args?.path ?? 'Untitled.txt';
  return <div className="productivity-app notepad-app">
    <div className="app-toolbar"><span>{path}</span><span className={saved ? 'save-state' : 'save-state dirty'}>{saved ? 'Saved' : 'Unsaved changes'}</span></div>
    <textarea value={text} onChange={event => { setText(event.target.value); setSaved(false); }} onBlur={() => setSaved(true)} placeholder="Start typing..." aria-label="Notepad document" />
    <footer className="app-status">{text.length} characters · Plain text</footer>
  </div>;
}

function Calculator() {
  const [display, setDisplay] = useState('0');
  const [memory, setMemory] = useState<number | null>(null);
  const append = (value: string) => setDisplay(current => current === '0' ? value : current + value);
  const calculate = () => {
    if (!/^[0-9+*/().% -]+$/.test(display)) return setDisplay('Error');
    try {
      const result = Function(`"use strict"; return (${display})`)();
      setDisplay(Number.isFinite(result) ? String(result) : 'Error');
    } catch { setDisplay('Error'); }
  };
  const clear = () => setDisplay('0');
  return <div className="productivity-app calculator-app">
    <output className="calculator-display" aria-live="polite">{display}</output>
    <div className="calculator-grid">
      {['MC','MR','M+','C','7','8','9','÷','4','5','6','×','1','2','3','-','0','.','%','+'].map(key => <button key={key} onClick={() => {
        if (key === 'C' || key === 'MC') return clear();
        if (key === 'MR') return memory !== null && setDisplay(String(memory));
        if (key === 'M+') return setMemory(Number(display) || 0);
        if (key === '÷') return append('/');
        if (key === '×') return append('*');
        append(key);
      }}>{key}</button>)}
      <button className="calculator-equals" onClick={calculate}>=</button>
    </div>
  </div>;
}

function Browser({ args, launch }: { args: AppArgs; launch: AppApi['launch'] }) {
  const [address, setAddress] = useState(args?.url ?? 'https://example.com');
  const [url, setUrl] = useState(address);
  const input = useRef<HTMLInputElement>(null);
  const navigate = () => { const next = address.match(/^https?:\/\//) ? address : `https://${address}`; setUrl(next); };
  return <div className="productivity-app browser-app">
    <form className="browser-toolbar" onSubmit={event => { event.preventDefault(); navigate(); }}><button type="button" onClick={() => input.current?.focus()} aria-label="Focus address bar">↻</button><input ref={input} value={address} onChange={event => setAddress(event.target.value)} aria-label="Address" /><button type="submit">Go</button></form>
    <div className="browser-hint">Browser mode is sandboxed. External pages may refuse to be embedded. <button onClick={() => launch('notepad', { path: 'Browser notes.txt' })}>Open notes</button></div>
    <iframe title="Browser preview" src={url} />
  </div>;
}

ApplicationRegistry.notepad.component = args => <Notepad args={args as AppArgs} />;
ApplicationRegistry.calculator.component = () => <Calculator />;
ApplicationRegistry.browser.component = (args, api) => <Browser args={args as AppArgs} launch={api.launch} />;
