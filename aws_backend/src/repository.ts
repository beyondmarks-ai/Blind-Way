import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  BatchGetCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  TransactWriteCommand,
} from "@aws-sdk/lib-dynamodb";

import type { Alert, AlertLocation, Device, Invite, Profile, Role, TrustedLink } from "./types.js";

const tableName = process.env.TABLE_NAME ?? "blind-way";
const db = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

type Item = Record<string, unknown>;
const clean = <T>(item: Item | undefined): T | undefined => {
  if (!item) return undefined;
  const { PK: _pk, SK: _sk, GSI1PK: _g1pk, GSI1SK: _g1sk, expiresAtEpoch: _ttl, ...value } = item;
  return value as T;
};

async function get<T>(PK: string, SK: string) {
  const result = await db.send(new GetCommand({ TableName: tableName, Key: { PK, SK } }));
  return clean<T>(result.Item);
}

async function query<T>(PK: string, prefix?: string) {
  const result = await db.send(new QueryCommand({
    TableName: tableName,
    KeyConditionExpression: prefix ? "PK = :pk AND begins_with(SK, :prefix)" : "PK = :pk",
    ExpressionAttributeValues: prefix ? { ":pk": PK, ":prefix": prefix } : { ":pk": PK },
  }));
  return (result.Items ?? []).map((item) => clean<T>(item)!).filter(Boolean);
}

export const repository = {
  async ensureProfile(
    id: string,
    role: Role,
    displayName: string,
    identity: { phone?: string; phoneVerified?: boolean } = {},
  ) {
    const existing = await this.profile(id);
    if (existing) {
      const updated: Profile = {
        ...existing,
        displayName,
        phone: identity.phone ?? existing.phone,
        phoneVerified: identity.phoneVerified ?? existing.phoneVerified,
        updatedAt: new Date().toISOString(),
      };
      await db.send(new PutCommand({
        TableName: tableName,
        Item: { PK: `USER#${id}`, SK: "PROFILE", ...updated },
      }));
      return updated;
    }
    const now = new Date().toISOString();
    const profile: Profile = {
      id,
      type: "profile",
      role,
      displayName,
      phone: identity.phone,
      phoneVerified: identity.phoneVerified ?? false,
      createdAt: now,
      updatedAt: now,
    };
    await db.send(new PutCommand({
      TableName: tableName,
      Item: { PK: `USER#${id}`, SK: "PROFILE", ...profile },
      ConditionExpression: "attribute_not_exists(PK)",
    })).catch(async (error: unknown) => {
      if ((error as { name?: string }).name !== "ConditionalCheckFailedException") throw error;
    });
    return (await this.profile(id)) ?? profile;
  },

  profile(id: string) { return get<Profile>(`USER#${id}`, "PROFILE"); },

  async profiles(ids: string[]) {
    if (!ids.length) return [];
    const result = await db.send(new BatchGetCommand({
      RequestItems: { [tableName]: { Keys: [...new Set(ids)].map((id) => ({ PK: `USER#${id}`, SK: "PROFILE" })) } },
    }));
    return (result.Responses?.[tableName] ?? []).map((item) => clean<Profile>(item)!).filter(Boolean);
  },

  saveDevice(device: Device) {
    return db.send(new PutCommand({ TableName: tableName, Item: { PK: `USER#${device.ownerId}`, SK: `DEVICE#${device.id}`, ...device } })).then(() => undefined);
  },
  devices(ownerId: string) { return query<Device>(`USER#${ownerId}`, "DEVICE#"); },

  saveInvite(invite: Invite) {
    return db.send(new PutCommand({
      TableName: tableName,
      Item: { PK: `INVITE#${invite.codeHash}`, SK: "META", ...invite, expiresAtEpoch: Math.floor(Date.parse(invite.expiresAt) / 1000) },
    })).then(() => undefined);
  },
  inviteByHash(hash: string) { return get<Invite>(`INVITE#${hash}`, "META"); },

  async saveLink(link: TrustedLink) {
    await db.send(new TransactWriteCommand({ TransactItems: [
      { Put: { TableName: tableName, Item: { PK: `USER#${link.blindUserId}`, SK: `LINK#${link.contactUserId}`, ...link } } },
      { Put: { TableName: tableName, Item: { PK: `USER#${link.contactUserId}`, SK: `REVERSE_LINK#${link.blindUserId}`, ...link } } },
    ] }));
  },
  linksForBlindUser(id: string) { return query<TrustedLink>(`USER#${id}`, "LINK#").then((items) => items.filter((x) => !x.revokedAt)); },
  linksForContact(id: string) { return query<TrustedLink>(`USER#${id}`, "REVERSE_LINK#").then((items) => items.filter((x) => !x.revokedAt)); },
  activeLink(blind: string, contact: string) { return get<TrustedLink>(`USER#${blind}`, `LINK#${contact}`).then((x) => x?.revokedAt ? undefined : x); },

  async saveAlert(alert: Alert) {
    await db.send(new PutCommand({
      TableName: tableName,
      Item: { PK: `ALERT#${alert.id}`, SK: "META", GSI1PK: `USER#${alert.blindUserId}`, GSI1SK: `ALERT#${alert.startedAt}#${alert.id}`, ...alert },
    }));
  },
  alert(id: string) { return get<Alert>(`ALERT#${id}`, "META"); },
  async saveIdempotency(userId: string, key: string, alertId: string) {
    await db.send(new PutCommand({ TableName: tableName, Item: { PK: `USER#${userId}`, SK: `IDEMPOTENCY#${key}`, alertId, expiresAtEpoch: Math.floor(Date.now() / 1000) + 86400 } }));
  },
  async alertByIdempotency(userId: string, key: string) {
    const item = await get<{ alertId: string }>(`USER#${userId}`, `IDEMPOTENCY#${key}`);
    return item?.alertId ? this.alert(item.alertId) : undefined;
  },
  async activeAlertsForBlindUser(id: string) {
    const result = await db.send(new QueryCommand({
      TableName: tableName,
      IndexName: "GSI1",
      KeyConditionExpression: "GSI1PK = :pk AND begins_with(GSI1SK, :prefix)",
      ExpressionAttributeValues: { ":pk": `USER#${id}`, ":prefix": "ALERT#" },
      ScanIndexForward: false,
      Limit: 25,
    }));
    return (result.Items ?? []).map((x) => clean<Alert>(x)!).filter((x) => ["active", "acknowledged"].includes(x.status));
  },
  async activeAlertsForContact(id: string) {
    const links = await this.linksForContact(id);
    const groups = await Promise.all(links.map((link) => this.activeAlertsForBlindUser(link.blindUserId)));
    return groups.flat().sort((a, b) => b.startedAt.localeCompare(a.startedAt));
  },
  saveLocation(location: AlertLocation) {
    return db.send(new PutCommand({
      TableName: tableName,
      Item: { PK: `ALERT#${location.alertId}`, SK: `LOCATION#${location.recordedAt}#${location.id}`, ...location, expiresAtEpoch: location.expiresAt },
    })).then(() => undefined);
  },
};
