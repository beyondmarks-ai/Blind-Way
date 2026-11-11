import { CosmosClient, type Container } from '@azure/cosmos';
import { DefaultAzureCredential } from '@azure/identity';
import { config } from './config.js';

export const memoryTtl = 7 * 24 * 60 * 60;
export type Conversation = { id: string; question: string; answer: string; recordedAt: string };
type Stored = Conversation & { partitionKey: string; expiresAt: number; ttl: number };
const local = new Map<string, Stored>();
let container: Container | undefined;
function store() {
  if (!config.COSMOS_ENDPOINT) return undefined;
  container ??= new CosmosClient({ endpoint: config.COSMOS_ENDPOINT, aadCredentials: new DefaultAzureCredential() })
    .database(config.COSMOS_DATABASE).container('conversation-memory');
  return container;
}
export async function saveConversation(user: string, item: Omit<Conversation, 'recordedAt'>) {
  const now = Date.now();
  const value: Stored = { ...item, recordedAt: new Date(now).toISOString(), partitionKey: user,
    expiresAt: Math.floor(now / 1000) + memoryTtl, ttl: memoryTtl };
  const db = store();
  if (db) await db.items.upsert(value);
  else local.set(`${user}:${item.id}`, value);
}
export async function recentConversations(user: string): Promise<Conversation[]> {
  const now = Math.floor(Date.now() / 1000);
  const db = store();
  const rows = db ? (await db.items.query<Stored>({
    query: 'SELECT TOP 12 * FROM c WHERE c.partitionKey=@user AND c.expiresAt>@now ORDER BY c.recordedAt DESC',
    parameters: [{ name: '@user', value: user }, { name: '@now', value: now }],
  }, { partitionKey: user }).fetchAll()).resources
    : [...local.values()].filter(x => x.partitionKey === user && x.expiresAt > now)
      .sort((a,b) => b.recordedAt.localeCompare(a.recordedAt)).slice(0,12);
  return rows.reverse().map(({ id, question, answer, recordedAt }) => ({ id, question, answer, recordedAt }));
}
