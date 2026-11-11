import {languages} from './languages.mjs';
export function decodeMessage(raw) {
  const m=JSON.parse(raw.toString());
  if(!m || typeof m!=='object') throw new Error('Invalid message');
  if(['begin','audio','end','observe','played'].includes(m.type) && (!Number.isSafeInteger(m.turn)||m.turn<1)) throw new Error('Invalid turn');
  if(m.type==='frame'||m.type==='audio') {
    const limit=m.type==='frame'?400000:16384;
    if(typeof m.data!=='string'||m.data.length>limit||!m.data.length||!/^[A-Za-z0-9+/]*={0,2}$/.test(m.data)) throw new Error('Invalid media');
    const bytes=Buffer.from(m.data,'base64');
    if(m.type==='frame' && (bytes[0]!==255||bytes[1]!==216||bytes.at(-2)!==255||bytes.at(-1)!==217)) throw new Error('Invalid JPEG');
    if(m.type==='audio' && bytes.length%2) throw new Error('Invalid PCM');
  }
  if(m.type==='observe' && (typeof m.language!=='string'||(!Object.hasOwn(languages,m.language)&&m.language!=='English')))throw new Error('Invalid language');
  if(m.type==='language' && (typeof m.language!=='string'||!Object.hasOwn(languages,m.language)))throw new Error('Invalid language');
  if(m.type==='navigationPrompt' && !['none','destination','start'].includes(m.prompt))throw new Error('Invalid navigation prompt');
  if(m.type==='navigationPrompt' && m.language!==undefined && !Object.hasOwn(languages,m.language))throw new Error('Invalid navigation language');
  if(!['frame','begin','audio','end','cancel','ping','observe','played','language','navigationPrompt'].includes(m.type)) throw new Error('Invalid message type');
  return m;
}
