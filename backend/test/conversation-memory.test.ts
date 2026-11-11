import {expect,it,vi} from 'vitest';
import {saveConversation,recentConversations,memoryTtl} from '../src/conversation-memory.js';

it('expires memory after seven days and bounds the loaded context',async()=>{
  vi.useFakeTimers();
  try {
    vi.setSystemTime(new Date('2026-11-09T00:00:00Z'));
    for(let n=0;n<15;n++) {
      await saveConversation('expiry-user',{id:`turn-${n}`,question:'Question',answer:`Answer ${n}`});
      vi.setSystemTime(Date.now()+1000);
    }
    const recent=await recentConversations('expiry-user');
    expect(recent).toHaveLength(12);expect(recent[0].answer).toBe('Answer 3');
    vi.setSystemTime(Date.now()+memoryTtl*1000);
    expect(await recentConversations('expiry-user')).toEqual([]);
  } finally {vi.useRealTimers();}
});
