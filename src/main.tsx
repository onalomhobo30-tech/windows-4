import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';
import { WindowManagerProvider, WindowManager, useWindowManager, type AppId } from './windowManager';
import { GlobalSearch, StartMenu } from './StartSurfaces';
import { ApplicationRegistry } from './windowManager';
import { PinningService, RecentItemsService } from './startServices';
import { SettingsService, ThemeService, SystemEventBus } from './systemServices';
import './productivityApps';

const desktop: { id: AppId; label: string; icon: string }[] = [
  { id: 'this-pc', label: 'This PC', icon: '💻' }, { id: 'file-explorer', label: 'My Files', icon: '📁' },
  { id: 'browser', label: 'Browser', icon: '🌐' }, { id: 'music', label: 'Music', icon: '🎵' },
  { id: 'video-player', label: 'Videos', icon: '🎬' }, { id: 'games', label: 'Games', icon: '🎮' },
  { id: 'settings', label: 'Settings', icon: '⚙️' }, { id: 'paint', label: 'Apps', icon: '🎨' },
];

function Shell() {
  const wm = useWindowManager();
  const [start, setStart] = useState(false), [search, setSearch] = useState(false), [selected, setSelected] = useState<AppId | null>(null);
  const [clock, setClock] = useState(new Date()), [overview, setOverview] = useState(false), [properties, setProperties] = useState<unknown>(null);
  const [pins, setPins] = useState(PinningService.getTaskbarPins()), [, setTick] = useState(0);
  useEffect(() => { const timer = window.setInterval(() => setClock(new Date()), 1000); return () => window.clearInterval(timer); }, []);
  useEffect(() => { ThemeService.apply(String(SettingsService.get('theme')), String(SettingsService.get('accent'))); return SystemEventBus.on('themeChanged', () => setTick(x => x + 1)); }, []);
  useEffect(() => { const key = (event: KeyboardEvent) => { if (event.key === 'Escape') { setStart(false); setSearch(false); setOverview(false); } if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 's') { event.preventDefault(); setSearch(true); setStart(false); } if ((event.metaKey || event.key.toLowerCase() === 'd')) { event.preventDefault(); document.querySelector('.desktop')?.classList.toggle('desktop-hidden'); } if ((event.metaKey || event.key === 'Meta') && event.key.toLowerCase() === 'w') { event.preventDefault(); setOverview(true); } }; window.addEventListener('keydown', key); return () => window.removeEventListener('keydown', key); }, []);
  const launch = (id: AppId, args?: unknown) => { const value = wm.launchApp(id, args); const app = ApplicationRegistry[id]; if (app) RecentItemsService.record({ id: `app-${id}`, type: 'application', name: app.name, icon: app.icon }); return value; };
  const clockText = SettingsService.get('clock24Hour', true) ? clock.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : clock.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', hour12: true });
  return <main className="desktop" onClick={() => { setStart(false); setSearch(false); }} onContextMenu={event => event.preventDefault()}>
    <div className="wallpaper" /><section className="icons">{desktop.map((item, index) => <button key={item.id} className={`icon ${selected === item.id ? 'selected' : ''}`} style={{ top: 18 + index * 76 }} onClick={event => { event.stopPropagation(); setSelected(item.id); }} onDoubleClick={event => { event.stopPropagation(); launch(item.id); }}><i>{item.icon}</i><span>{item.label}</span></button>)}</section>
    <WindowManager showProperties={setProperties} />{overview && <div className="wm-overview"><h2>Window overview</h2>{wm.windows.map(win => <button key={win.id} onClick={() => { wm.focusWindow(win.id); setOverview(false); }}>{win.icon}<b>{win.title}</b><small>{win.isMinimized ? 'Minimized' : 'Running'}</small><em onClick={event => { event.stopPropagation(); wm.closeWindow(win.id); }}>×</em></button>)}</div>}
    {properties && <div className="properties"><h3>Properties</h3><p>{(properties as { name?: string }).name ?? 'Selected item'}</p><button onClick={() => setProperties(null)}>Close</button></div>}
    <StartMenu open={start} onClose={() => setStart(false)} launch={launch} /><GlobalSearch open={search} onClose={() => setSearch(false)} launch={launch} />
    <footer className="taskbar"><button className="startBtn" onClick={event => { event.stopPropagation(); setStart(x => !x); setSearch(false); }}>◈ Windows 4</button><button className="searchBtn" onClick={event => { event.stopPropagation(); setSearch(true); setStart(false); }}>⌕</button><div className="pinned">{pins.map(id => <button key={id} onClick={() => launch(id)}>{ApplicationRegistry[id]?.icon}</button>)}</div><div className="running">{wm.windows.map(win => <button className={wm.activeId === win.id ? 'run active' : 'run'} key={win.id} onClick={() => win.isMinimized ? wm.restoreWindow(win.id) : wm.activeId === win.id ? wm.minimizeWindow(win.id) : wm.focusWindow(win.id)}>{win.icon}</button>)}</div><div className="tray"><button onClick={() => launch('settings')}>⚙</button><button onClick={() => launch('settings')}>🔊</button><span>{clockText}</span><small>{clock.toLocaleDateString([], { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' })}</small></div></footer>
  </main>;
}
function App() { return <WindowManagerProvider><Shell /></WindowManagerProvider>; }
createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
