export type FileKind = 'folder' | 'file' | 'drive' | 'trash';
export type ViewMode = 'large' | 'medium' | 'small' | 'list' | 'details';
export interface FsNode { id: string; name: string; path: string; kind: FileKind; extension?: string; size: number; created: string; modified: string; parent: string; content?: string; originalPath?: string; deletedAt?: string; }
export interface FileSystemAdapter { list(): Promise<FsNode[]>; save(nodes: FsNode[]): Promise<void>; }

const DB = 'huskagent-windows4-files';
const STORE = 'nodes';
const now = () => new Date().toISOString();
const id = () => crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`;
const seed: FsNode[] = [
  { id:'root-c', name:'Local Disk (C:)', path:'C:', kind:'drive', size:0, created:now(), modified:now(), parent:'This PC' },
  { id:'root-d', name:'Data (D:)', path:'D:', kind:'drive', size:0, created:now(), modified:now(), parent:'This PC' },
  ...['Desktop','Documents','Downloads','Music','Pictures','Videos'].map(name => ({ id:id(), name, path:`C:/${name}`, kind:'folder' as const, size:0, created:now(), modified:now(), parent:'C:' })),
  { id:id(), name:'Welcome.txt', path:'C:/Documents/Welcome.txt', kind:'file', extension:'TXT', size:92, created:now(), modified:now(), parent:'C:/Documents', content:'Welcome to HUSKAGENT WINDOWS 4.\nYour browser filesystem is persistent.' },
];

export class BrowserFileSystemAdapter implements FileSystemAdapter {
  async list() {
    const saved = localStorage.getItem(DB);
    if (saved) return JSON.parse(saved) as FsNode[];
    await this.save(seed); return seed;
  }
  async save(nodes: FsNode[]) { localStorage.setItem(DB, JSON.stringify(nodes)); }
}
export class NativeFileSystemAdapter implements FileSystemAdapter { async list(){ throw new Error('Native adapter requires the packaged desktop host.'); } async save(){ throw new Error('Native adapter requires the packaged desktop host.'); } }

export class FileSystemService {
  constructor(private adapter: FileSystemAdapter = new BrowserFileSystemAdapter()) {}
  async all() { return this.adapter.list(); }
  async listDirectory(path: string) { const nodes = await this.all(); return nodes.filter(n => n.parent === path && n.kind !== 'trash'); }
  async search(query: string) { const q=query.toLowerCase(); return (await this.all()).filter(n=>n.kind !== 'trash' && (n.name.toLowerCase().includes(q) || n.extension?.toLowerCase().includes(q))); }
  async exists(path: string) { return (await this.all()).some(n=>n.path===path); }
  async createFolder(parent: string, name: string) { return this.create(parent,name,'folder'); }
  async createFile(parent: string, name: string, content='') { return this.create(parent,name,'file',content); }
  private async create(parent:string,name:string,kind:FileKind,content='') { const nodes=await this.all(); if(nodes.some(n=>n.parent===parent&&n.name===name)) throw new Error('An item with that name already exists.'); const stamp=now(); const extension=kind==='file' ? name.split('.').pop()?.toUpperCase() : undefined; const node={id:id(),name,path:`${parent}/${name}`,kind,extension,size:content.length,created:stamp,modified:stamp,parent,content}; nodes.push(node); await this.adapter.save(nodes); return node; }
  async readFile(path:string) { const node=(await this.all()).find(n=>n.path===path); return node?.content ?? ''; }
  async writeFile(path:string,data:string) { const nodes=await this.all(); const n=nodes.find(x=>x.path===path); if(!n) throw new Error('File not found'); n.content=data; n.size=data.length; n.modified=now(); await this.adapter.save(nodes); }
  async rename(path:string,name:string) { const nodes=await this.all(); const n=nodes.find(x=>x.path===path); if(!n) throw new Error('Item not found'); if(nodes.some(x=>x.parent===n.parent&&x.name===name)) throw new Error('An item with that name already exists.'); const old=n.path; n.name=name; n.path=`${n.parent}/${name}`; n.extension=n.kind==='file'?name.split('.').pop()?.toUpperCase():undefined; nodes.filter(x=>x.path.startsWith(`${old}/`)).forEach(x=>{x.path=x.path.replace(old,n.path);x.parent=x.parent.replace(old,n.path)}); await this.adapter.save(nodes); return n; }
  async move(path:string,destination:string) { const nodes=await this.all(); const n=nodes.find(x=>x.path===path); if(!n) throw new Error('Item not found'); const old=n.path; n.parent=destination; n.path=`${destination}/${n.name}`; nodes.filter(x=>x.path.startsWith(`${old}/`)).forEach(x=>{x.path=x.path.replace(old,n.path);x.parent=x.parent.replace(old,n.path)}); await this.adapter.save(nodes); }
  async copy(path:string,destination:string) { const nodes=await this.all(); const source=nodes.find(x=>x.path===path); if(!source) throw new Error('Item not found'); const copy={...source,id:id(),parent:destination,path:`${destination}/${source.name}`,created:now(),modified:now()}; nodes.push(copy); await this.adapter.save(nodes); return copy; }
  async trash(path:string) { const nodes=await this.all(); const n=nodes.find(x=>x.path===path); if(!n) return; n.originalPath=n.path; n.deletedAt=now(); n.kind='trash'; n.parent='Recycle Bin'; await this.adapter.save(nodes); }
  async recycle() { return (await this.all()).filter(n=>n.kind==='trash'); }
  async restore(idValue:string) { const nodes=await this.all(); const n=nodes.find(x=>x.id===idValue); if(!n) return; n.kind='file'; const original=n.originalPath ?? 'C:/Documents/'+n.name; n.path=original; n.parent=original.includes('/')?original.slice(0,original.lastIndexOf('/')):'C:'; delete n.originalPath; delete n.deletedAt; await this.adapter.save(nodes); }
  async permanentlyDelete(idValue:string) { const nodes=await this.all(); await this.adapter.save(nodes.filter(n=>n.id!==idValue)); }
  async emptyRecycleBin() { const nodes=await this.all(); await this.adapter.save(nodes.filter(n=>n.kind!=='trash')); }
}
export const fileSystem = new FileSystemService();
export const formatSize=(bytes:number)=>bytes<1024?`${bytes} B`:`${(bytes/1024).toFixed(1)} KB`;
export const fileIcon=(node:FsNode)=>node.kind==='folder'?'📁':node.kind==='drive'?'💽':node.kind==='trash'?'🗑️':({TXT:'📝',PDF:'📕',DOC:'📘',DOCX:'📘',JPG:'🖼️',JPEG:'🖼️',PNG:'🖼️',GIF:'🖼️',MP3:'🎵',WAV:'🎵',MP4:'🎬',ZIP:'🗜️',APK:'📦',EXE:'⚙️'}[node.extension??'']??'📄');
