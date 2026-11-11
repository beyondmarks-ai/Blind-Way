import { CosmosClient, type Container, type SqlParameter } from "@azure/cosmos";
import { DefaultAzureCredential } from "@azure/identity";

import { config } from "./config.js";
import type { Alert, AlertLocation, Device, Invite, Profile, Role, TrustedLink } from "./types.js";

type Stored<T> = T & { partitionKey: string };

export interface Repository {
  ensureProfile(id: string, role: Role, displayName: string): Promise<Profile>;
  profile(id: string): Promise<Profile | undefined>;
  saveDevice(device: Device): Promise<void>;
  devices(ownerIds: string[]): Promise<Device[]>;
  saveInvite(invite: Invite): Promise<void>;
  inviteByHash(hash: string): Promise<Invite | undefined>;
  saveLink(link: TrustedLink): Promise<void>;
  linksForBlindUser(userId: string): Promise<TrustedLink[]>;
  linksForContact(userId: string): Promise<TrustedLink[]>;
  activeLink(blindUserId: string, contactUserId: string): Promise<TrustedLink | undefined>;
  saveAlert(alert: Alert): Promise<void>;
  alert(id: string): Promise<Alert | undefined>;
  alertByIdempotency(userId: string, key: string): Promise<Alert | undefined>;
  activeAlertsForContact(userId: string): Promise<Alert[]>;
  activeAlertsForBlindUser(userId: string): Promise<Alert[]>;
  saveLocation(location: AlertLocation): Promise<void>;
}

export class MemoryRepository implements Repository {
  profiles = new Map<string, Profile>();
  deviceItems = new Map<string, Device>();
  invites = new Map<string, Invite>();
  links = new Map<string, TrustedLink>();
  alerts = new Map<string, Alert>();
  locations = new Map<string, AlertLocation>();

  async ensureProfile(id: string, role: Role, displayName: string) {
    const existing = this.profiles.get(id);
    if (existing) return existing;
    const now = new Date().toISOString();
    const profile: Profile = { id, type: "profile", role, displayName, phoneVerified: false, createdAt: now, updatedAt: now };
    this.profiles.set(id, profile);
    return profile;
  }
  async profile(id: string) { return this.profiles.get(id); }
  async saveDevice(device: Device) {
    for(const [id,old] of this.deviceItems)if(old.pushToken===device.pushToken&&id!==device.id)this.deviceItems.delete(id);
    this.deviceItems.set(device.id, device);
  }
  async devices(ownerIds: string[]) { return [...this.deviceItems.values()].filter((d) => ownerIds.includes(d.ownerId)); }
  async saveInvite(invite: Invite) { this.invites.set(invite.id, invite); }
  async inviteByHash(hash: string) { return [...this.invites.values()].find((i) => i.codeHash === hash); }
  async saveLink(link: TrustedLink) { this.links.set(link.id, link); }
  async linksForBlindUser(id: string) { return [...this.links.values()].filter((l) => l.blindUserId === id && !l.revokedAt); }
  async linksForContact(id: string) { return [...this.links.values()].filter((l) => l.contactUserId === id && !l.revokedAt); }
  async activeLink(blind: string, contact: string) { return [...this.links.values()].find((l) => l.blindUserId === blind && l.contactUserId === contact && !l.revokedAt); }
  async saveAlert(alert: Alert) { this.alerts.set(alert.id, alert); }
  async alert(id: string) { return this.alerts.get(id); }
  async alertByIdempotency(userId: string, key: string) { return [...this.alerts.values()].find((a) => a.blindUserId === userId && a.idempotencyKey === key); }
  async activeAlertsForContact(userId: string) {
    const links = await this.linksForContact(userId);
    const ids = links.map((link) => link.blindUserId);
    return [...this.alerts.values()].filter((a) => ids.includes(a.blindUserId) && ["active", "acknowledged"].includes(a.status));
  }
  async activeAlertsForBlindUser(userId: string) {
    return [...this.alerts.values()].filter((alert) =>
      alert.blindUserId === userId && ["active", "acknowledged"].includes(alert.status));
  }
  async saveLocation(location: AlertLocation) { this.locations.set(location.id, location); }
}

class CosmosRepository implements Repository {
  private containerPromise?: Promise<Container>;

  private async container(): Promise<Container> {
    this.containerPromise ??= (async () => {
      const client = new CosmosClient({ endpoint: config.COSMOS_ENDPOINT!, aadCredentials: new DefaultAzureCredential() });
      // Infrastructure provisions these resources. The managed identity has
      // data permissions, not permission to create database metadata.
      return client.database(config.COSMOS_DATABASE).container('items');
    })();
    return this.containerPromise;
  }

  private async upsert<T extends { id: string }>(item: Stored<T>) { await (await this.container()).items.upsert(item); }
  private async query<T>(text: string, parameters: SqlParameter[]): Promise<T[]> {
    const result = await (await this.container()).items.query<T>({ query: text, parameters }).fetchAll();
    return result.resources;
  }
  async ensureProfile(id: string, role: Role, displayName: string) {
    const existing = await this.profile(id);
    if (existing) return existing;
    const now = new Date().toISOString();
    const profile: Profile = { id, type: "profile", role, displayName, phoneVerified: false, createdAt: now, updatedAt: now };
    try {
      await (await this.container()).items.create({ ...profile, partitionKey: id });
    } catch (error) {
      if ((error as { code?: number }).code !== 409) throw error;
      const concurrent = await this.profile(id);
      if (!concurrent) throw error;
      return concurrent;
    }
    return profile;
  }
  async profile(id: string) { return (await this.query<Profile>("SELECT * FROM c WHERE c.type='profile' AND c.id=@id", [{ name: "@id", value: id }]))[0]; }
  async saveDevice(device: Device) {
    const previous=await this.query<Device>("SELECT * FROM c WHERE c.type='device' AND c.pushToken=@token",[{name:'@token',value:device.pushToken}]);
    for(const old of previous)if(old.id!==device.id)await (await this.container()).item(old.id,old.ownerId).delete();
    await this.upsert({ ...device, partitionKey: device.ownerId });
  }
  async devices(ids: string[]) { return ids.length ? this.query<Device>("SELECT * FROM c WHERE c.type='device' AND ARRAY_CONTAINS(@ids,c.ownerId)", [{ name: "@ids", value: ids }]) : []; }
  async saveInvite(invite: Invite) { await this.upsert({ ...invite, partitionKey: invite.blindUserId }); }
  async inviteByHash(hash: string) { return (await this.query<Invite>("SELECT * FROM c WHERE c.type='invite' AND c.codeHash=@hash", [{ name: "@hash", value: hash }]))[0]; }
  async saveLink(link: TrustedLink) { await this.upsert({ ...link, partitionKey: link.blindUserId }); }
  async linksForBlindUser(id: string) { return this.query<TrustedLink>("SELECT * FROM c WHERE c.type='link' AND c.blindUserId=@id AND NOT IS_DEFINED(c.revokedAt)", [{ name: "@id", value: id }]); }
  async linksForContact(id: string) { return this.query<TrustedLink>("SELECT * FROM c WHERE c.type='link' AND c.contactUserId=@id AND NOT IS_DEFINED(c.revokedAt)", [{ name: "@id", value: id }]); }
  async activeLink(blind: string, contact: string) { return (await this.query<TrustedLink>("SELECT * FROM c WHERE c.type='link' AND c.blindUserId=@blind AND c.contactUserId=@contact AND NOT IS_DEFINED(c.revokedAt)", [{ name: "@blind", value: blind }, { name: "@contact", value: contact }]))[0]; }
  async saveAlert(alert: Alert) { await this.upsert({ ...alert, partitionKey: alert.blindUserId }); }
  async alert(id: string) { return (await this.query<Alert>("SELECT * FROM c WHERE c.type='alert' AND c.id=@id", [{ name: "@id", value: id }]))[0]; }
  async alertByIdempotency(id: string, key: string) { return (await this.query<Alert>("SELECT * FROM c WHERE c.type='alert' AND c.blindUserId=@id AND c.idempotencyKey=@key", [{ name: "@id", value: id }, { name: "@key", value: key }]))[0]; }
  async activeAlertsForContact(id: string) {
    const links = await this.linksForContact(id);
    const ids = links.map((link) => link.blindUserId);
    return ids.length ? this.query<Alert>("SELECT * FROM c WHERE c.type='alert' AND ARRAY_CONTAINS(@ids,c.blindUserId) AND ARRAY_CONTAINS(['active','acknowledged'],c.status)", [{ name: "@ids", value: ids }]) : [];
  }
  async activeAlertsForBlindUser(id: string) {
    return this.query<Alert>("SELECT * FROM c WHERE c.type='alert' AND c.blindUserId=@id AND ARRAY_CONTAINS(['active','acknowledged'],c.status)", [{ name: "@id", value: id }]);
  }
  async saveLocation(location: AlertLocation) { await this.upsert({ ...location, partitionKey: location.alertId }); }
}

export const repository: Repository = config.COSMOS_ENDPOINT ? new CosmosRepository() : new MemoryRepository();
