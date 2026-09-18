import { fileSystem } from './filesystem';

export type Platform = 'browser' | 'desktop' | 'native';
export type SystemCapability = { supported: boolean; value?: unknown; reason?: string };
export type SettingsValue = string | number | boolean;

const SETTINGS_KEY = 'huskagent-windows4-settings';
const DEFAULTS: Record<string, SettingsValue> = {
  theme: 'Windows 4 Dark', accent: 'indigo', wallpaper: 'default', transparency: true,
  clock24Hour: true, textScale: 100, highContrast: false, reducedMotion: false,
  notifications: true, notificationSounds: true, defaultTxt: 'notepad', defaultMp3: 'music',
  defaultImage: 'paint', defaultVideo: 'video-player', defaultPdf: 'browser',
};

export const SettingsService = {
  get<T extends SettingsValue>(key: string, fallback = DEFAULTS[key] as T): T { try { const saved = JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}'); return (saved[key] ?? fallback) as T; } catch { return fallback; } },
  set(key: string, value: SettingsValue) { const saved = JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}'); saved[key] = value; localStorage.setItem(SETTINGS_KEY, JSON.stringify(saved)); SystemEventBus.emit('settingsChanged', { key, value }); },
  all() { try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}') }; } catch { return { ...DEFAULTS }; } },
};

export const SystemEventBus = { listeners: new Map<string, Set<(detail?: unknown) => void>>(), on(event: string, listener: (detail?: unknown) => void) { const set = this.listeners.get(event) || new Set(); set.add(listener); this.listeners.set(event, set); return () => set.delete(listener); }, emit(event: string, detail?: unknown) { this.listeners.get(event)?.forEach(listener => listener(detail)); } };

export const PlatformService = { getPlatform(): Platform { return 'browser'; } };
export const SystemService = { getPlatform: () => PlatformService.getPlatform(), getCapability: (value: unknown): SystemCapability => ({ supported: value !== undefined, value }) };

export const DisplayService = { async getDisplays() { return [{ id: 'browser-display', name: 'Browser Display', primary: true }]; }, async getResolution() { return { supported: true, value: `${screen.width} × ${screen.height}` }; }, async getScale() { return { supported: true, value: window.devicePixelRatio || 1 }; }, async getBrightness() { return { supported: false, reason: 'Browser applications cannot read monitor brightness.' }; }, async setBrightness() { return { supported: false, reason: 'Brightness control requires a native Windows 4 host.' }; }, async getOrientation() { return { supported: true, value: screen.orientation?.type || 'unknown' }; }, async setOrientation() { return { supported: false, reason: 'Orientation control requires a native Windows 4 host.' }; }, async getRefreshRate() { return { supported: false, reason: 'Refresh rate is not exposed by this browser.' }; } };

export const AudioService = { async getOutputDevices() { if (!navigator.mediaDevices?.enumerateDevices) return { supported: false }; return { supported: true, value: (await navigator.mediaDevices.enumerateDevices()).filter(x => x.kind === 'audiooutput').map(x => x.label || 'Audio output') }; }, async getInputDevices() { if (!navigator.mediaDevices?.enumerateDevices) return { supported: false }; return { supported: true, value: (await navigator.mediaDevices.enumerateDevices()).filter(x => x.kind === 'audioinput').map(x => x.label || 'Audio input') }; }, getVolume() { return { supported: false, reason: 'Browser pages cannot read system volume.' }; }, setVolume() { return { supported: false, reason: 'Use the browser or native Windows 4 host audio controls.' }; }, setMuted() { return { supported: false, reason: 'System mute is unavailable in browser mode.' }; }, getInputVolume() { return { supported: false, reason: 'Input volume is native-only.' }; } };

export const PowerService = { async getBattery() { const battery = (navigator as Navigator & { getBattery?: () => Promise<{ level:number; charging:boolean }> }).getBattery; if (!battery) return { supported: false, reason: 'Battery API unavailable.' }; const value = await battery(); return { supported: true, value: { percentage: Math.round(value.level * 100), charging: value.charging } }; }, getPowerMode: () => ({ supported: false, reason: 'Power mode is native-only.' }), setPowerMode: () => ({ supported: false, reason: 'Power mode is native-only.' }), getScreenTimeout: () => ({ supported: false, reason: 'Screen timeout is native-only.' }), setScreenTimeout: () => ({ supported: false, reason: 'Screen timeout is native-only.' }), getSleepTimeout: () => ({ supported: false, reason: 'Sleep timeout is native-only.' }), setSleepTimeout: () => ({ supported: false, reason: 'Sleep timeout is native-only.' }) };

export const NetworkService = { getOnlineStatus: () => ({ supported: true, value: navigator.onLine }), getConnectionType: () => ({ supported: true, value: (navigator as Navigator & { connection?: { effectiveType?: string } }).connection?.effectiveType || 'unknown' }), getConnectionStatus: () => ({ supported: true, value: navigator.onLine ? 'Online' : 'Offline' }), getNetworkInformation: () => ({ supported: false, reason: 'Detailed network information is available in native Windows 4.' }) };
export const BluetoothService = { isSupported: () => Boolean((navigator as Navigator & { bluetooth?: unknown }).bluetooth), isEnabled: () => ({ supported: false, reason: 'Bluetooth power state is not exposed in browser mode.' }), getDevices: () => ({ supported: false, reason: 'Device enumeration requires an explicit browser permission.' }), requestDevice: async () => { const bluetooth = (navigator as Navigator & { bluetooth?: { requestDevice: (options: unknown) => Promise<unknown> } }).bluetooth; return bluetooth ? bluetooth.requestDevice({ acceptAllDevices: true }) : Promise.reject(new Error('Web Bluetooth is unavailable.')); }, connect: () => ({ supported: false }), disconnect: () => ({ supported: false }) };
export const NotificationService = { supported: 'Notification' in window, permission: () => 'Notification' in window ? Notification.permission : 'unsupported', async requestPermission() { return 'Notification' in window ? Notification.requestPermission() : 'unsupported'; } };
export const StorageService = { async getUsage() { const nodes = await fileSystem.all(); const by = (term: string) => nodes.filter(n => n.path.toLowerCase().includes(term)).reduce((sum, n) => sum + n.size, 0); return { total: nodes.reduce((sum, n) => sum + n.size, 0), Documents: by('/documents'), Downloads: by('/downloads'), Music: by('/music'), Pictures: by('/pictures'), Videos: by('/videos') }; } };
export const UpdateService = { getCurrentVersion: () => ({ version: '1.0', build: '1000' }), checkForUpdates: () => ({ supported: false, reason: 'Updates require a native Windows 4 distribution service.' }), getUpdateStatus: () => ({ supported: true, value: 'Development build' }) };
export const ThemeService = { themes: ['Windows 4 Dark', 'Windows 4 Light', 'Windows 4 Midnight', 'Windows 4 Purple'], accents: ['blue', 'indigo', 'purple', 'red'], apply(theme: string, accent: string) { SettingsService.set('theme', theme); SettingsService.set('accent', accent); document.documentElement.dataset.theme = theme.toLowerCase().replaceAll(' ', '-'); document.documentElement.dataset.accent = accent; SystemEventBus.emit('themeChanged', { theme, accent }); } };
export const BrowserSystemAdapter = { platform: 'browser' as Platform };
export const NativeSystemAdapter = { platform: 'native' as Platform, supported: false };
