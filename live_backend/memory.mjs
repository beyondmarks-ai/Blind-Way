import {randomUUID} from 'node:crypto';
// Keep persistence off the audio path. Only acknowledged, completed playback is saved.
export class ConversationMemory {
  constructor(authorization, send, fetcher=fetch) { this.authorization=authorization;this.send=send;this.fetcher=fetcher;this.pending=new Map();this.recent=[]; }
  async load() {
    try {
      const response=await this.fetcher(`${process.env.AZURE_API_BASE_URL}/v1/live/memory`,{
        headers:{Authorization:this.authorization},signal:AbortSignal.timeout(3000)});
      if(!response.ok)throw new Error('Memory unavailable');
      const data=await response.json();this.recent=data.turns.slice(-12);
      this.send({type:'memory',available:true,count:this.recent.length});
    } catch {this.send({type:'memory',available:false});}
    return this.recent;
  }
  begin(turn,automatic=false) { this.pending.set(turn,{id:randomUUID(),question:automatic?'Automatic surroundings update':'',answer:'',complete:false}); }
  event(event) {
    const entry=this.pending.get(event.turn);if(!entry)return;
    if(event.type==='transcript')entry.question=(entry.question+event.text).slice(0,1500);
    if(event.type==='answer')entry.answer=(entry.answer+event.text).slice(0,3000);
    if(event.type==='end')entry.complete=true;
  }
  async played(turn) {
    const entry=this.pending.get(turn);this.pending.delete(turn);
    if(!entry?.complete||!entry.answer.trim())return;
    const {complete,...body}=entry;
    this.recent=[...this.recent,{...body,recordedAt:new Date().toISOString()}].slice(-12);
    try {
      const response=await this.fetcher(`${process.env.AZURE_API_BASE_URL}/v1/live/memory`,{
        method:'POST',headers:{Authorization:this.authorization,'Content-Type':'application/json'},
        body:JSON.stringify(body),signal:AbortSignal.timeout(4000)});
      if(!response.ok)throw new Error('Memory unavailable');
      this.send({type:'memory',available:true,count:this.recent.length});
    } catch {this.send({type:'memory',available:false});}
  }
  cancel() {this.pending.clear();}
}
