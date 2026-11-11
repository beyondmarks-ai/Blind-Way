import { BlobServiceClient } from '@azure/storage-blob';

function container() {
  const connection = process.env.AzureWebJobsStorage;
  if (!connection) throw new Error('Emergency snapshot storage is not configured.');
  return BlobServiceClient.fromConnectionString(connection).getContainerClient('emergency-snapshots');
}

export async function storeEmergencySnapshot(userId: string, alertId: string, imageBase64: string) {
  if (imageBase64.length > 2_000_000) throw new Error('Emergency snapshot exceeds 1.5 MB.');
  const image = Buffer.from(imageBase64, 'base64');
  if (image.length < 4 || image.length > 1_500_000 || image[0] !== 255 || image[1] !== 216 || image.at(-2) !== 255 || image.at(-1) !== 217) {
    throw new Error('Emergency snapshot is not a valid JPEG.');
  }
  const key = `alerts/${encodeURIComponent(userId)}/${alertId}/last-seen.jpg`;
  const client = container();
  await client.createIfNotExists(); // Private by default; account also denies public blobs.
  await client.getBlockBlobClient(key).uploadData(image, {
    blobHTTPHeaders: { blobContentType: 'image/jpeg', blobCacheControl: 'no-store' },
  });
  return key;
}

export async function emergencySnapshot(key: string) {
  return container().getBlobClient(key).downloadToBuffer();
}

export async function deleteEmergencySnapshot(key?: string) {
  if (key) await container().getBlobClient(key).deleteIfExists();
}
