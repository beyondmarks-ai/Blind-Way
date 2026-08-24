import { DeleteObjectCommand, GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

const s3 = new S3Client({});

function bucket() {
  const value = process.env.SNAPSHOT_BUCKET;
  if (!value) throw new Error("Emergency snapshot storage is not configured.");
  return value;
}

export async function storeEmergencySnapshot(
  blindUserId: string,
  alertId: string,
  imageBase64: string,
) {
  if (imageBase64.length > 2_100_000) throw new Error("Emergency snapshot exceeds 1.5 MB.");
  const image = Buffer.from(imageBase64, "base64");
  if (image.length < 4 || image[0] !== 0xff || image[1] !== 0xd8 || image.at(-2) !== 0xff || image.at(-1) !== 0xd9) {
    throw new Error("Emergency snapshot is not a valid JPEG.");
  }
  const key = `alerts/${encodeURIComponent(blindUserId)}/${alertId}/last-seen.jpg`;
  await s3.send(new PutObjectCommand({
    Bucket: bucket(),
    Key: key,
    Body: image,
    ContentType: "image/jpeg",
    CacheControl: "no-store",
    ServerSideEncryption: "AES256",
  }));
  return key;
}

export async function emergencySnapshot(key: string) {
  const result = await s3.send(new GetObjectCommand({ Bucket: bucket(), Key: key }));
  if (!result.Body) throw new Error("Emergency snapshot has no content.");
  return new Uint8Array(await result.Body.transformToByteArray());
}

export async function deleteEmergencySnapshot(key?: string) {
  if (!key) return;
  await s3.send(new DeleteObjectCommand({ Bucket: bucket(), Key: key }));
}
