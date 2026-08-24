export type Role = "blindUser" | "emergencyContact";
export type AlertStatus = "active" | "acknowledged" | "resolved" | "cancelled";

export interface AuthenticatedUser {
  sub: string;
  name?: string;
  email?: string;
}

export interface Profile {
  id: string;
  type: "profile";
  role: Role;
  displayName: string;
  phone?: string;
  phoneVerified: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface Device {
  id: string;
  type: "device";
  ownerId: string;
  platform: "android";
  pushToken: string;
  updatedAt: string;
}

export interface Invite {
  id: string;
  type: "invite";
  blindUserId: string;
  codeHash: string;
  expiresAt: string;
  redeemedBy?: string;
  redeemedAt?: string;
}

export interface TrustedLink {
  id: string;
  type: "link";
  blindUserId: string;
  contactUserId: string;
  createdAt: string;
  revokedAt?: string;
}

export interface Alert {
  id: string;
  type: "alert";
  blindUserId: string;
  status: AlertStatus;
  startedAt: string;
  latitude?: number;
  longitude?: number;
  accuracy?: number;
  acknowledgedBy?: string;
  acknowledgedAt?: string;
  resolvedBy?: string;
  resolvedAt?: string;
  idempotencyKey: string;
  smsEscalatedAt?: string;
}

export interface AlertLocation {
  id: string;
  type: "location";
  alertId: string;
  blindUserId: string;
  latitude: number;
  longitude: number;
  accuracy: number;
  recordedAt: string;
  ttl: number;
}
