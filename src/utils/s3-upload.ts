import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import fs from "fs";
import { randomUUID } from "crypto";
import path from "path";

export type S3Config = {
  region: string;
  bucketName: string;
  accessKeyId: string;
  secretAccessKey: string;
  transferAcceleration?: boolean;
};

export type S3UploadResult = {
  url: string;
  key: string;
};

/**
 * Upload a local file to S3
 * @param filePath - The local file path to upload
 * @param config - S3 configuration
 * @returns Promise<S3UploadResult> - The S3 URL and key
 */
export async function uploadFileToS3(
  filePath: string,
  config: S3Config,
): Promise<S3UploadResult> {
  const { Logger } = await import("./logger.js");

  try {
    // Read file from disk
    if (!fs.existsSync(filePath)) {
      throw new Error(`File not found: ${filePath}`);
    }

    const fileBuffer = fs.readFileSync(filePath);
    const fileExtension = path.extname(filePath).toLowerCase();
    
    // Determine content type based on file extension
    let contentType = "application/octet-stream";
    if (fileExtension === ".png") {
      contentType = "image/png";
    } else if (fileExtension === ".svg") {
      contentType = "image/svg+xml";
    } else if (fileExtension === ".jpg" || fileExtension === ".jpeg") {
      contentType = "image/jpeg";
    }

    // Generate unique key (using UUID to avoid collisions)
    const fileKey = randomUUID();

    // Create S3 client
    const s3Client = new S3Client({
      region: config.region,
      credentials: {
        accessKeyId: config.accessKeyId,
        secretAccessKey: config.secretAccessKey,
      },
    });

    // Create presigned URL for upload
    const command = new PutObjectCommand({
      Bucket: config.bucketName,
      Key: fileKey,
      ACL: "public-read",
      ContentType: contentType,
      ContentLength: fileBuffer.length,
    });

    const presignedUrl = await getSignedUrl(s3Client, command, {
      expiresIn: 60 * 60, // 1 hour
    });

    // Upload file using presigned URL
    Logger.log(`Uploading ${filePath} to S3 (${fileBuffer.length} bytes)...`);
    const uploadResponse = await fetch(presignedUrl, {
      method: "PUT",
      body: fileBuffer,
      headers: {
        "Content-Type": contentType,
        "Content-Length": fileBuffer.length.toString(),
      },
    });

    if (!uploadResponse.ok) {
      throw new Error(
        `S3 upload failed: ${uploadResponse.status} ${uploadResponse.statusText}`,
      );
    }

    // Generate public URL
    const s3Url = getS3PublicUrl({
      key: fileKey,
      bucketName: config.bucketName,
      region: config.region,
      transferAcceleration: config.transferAcceleration,
    });

    Logger.log(`Successfully uploaded to S3: ${s3Url}`);

    return {
      url: s3Url,
      key: fileKey,
    };
  } catch (error) {
    const { Logger } = await import("./logger.js");
    Logger.error(`Failed to upload ${filePath} to S3:`, error);
    throw error;
  }
}

/**
 * Generate public S3 URL
 */
function getS3PublicUrl({
  key,
  bucketName,
  region,
  transferAcceleration = false,
}: {
  key: string;
  bucketName: string;
  region: string;
  transferAcceleration?: boolean;
}): string {
  if (transferAcceleration) {
    return `https://${bucketName}.s3-accelerate.amazonaws.com/${key}`;
  }
  return `https://${bucketName}.s3.${region}.amazonaws.com/${key}`;
}

/**
 * Get S3 configuration from environment variables
 */
export function getS3ConfigFromEnv(): S3Config | null {
  const region = process.env.AWS_REGION;
  const bucketName = process.env.AWS_BUCKET_NAME;
  const accessKeyId = process.env.AWS_ACCESS_KEY_ID;
  const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;
  const transferAcceleration = process.env.AWS_TRANSFER_ACCELERATION === "true";

  if (!region || !bucketName || !accessKeyId || !secretAccessKey) {
    return null;
  }

  return {
    region,
    bucketName,
    accessKeyId,
    secretAccessKey,
    transferAcceleration,
  };
}
