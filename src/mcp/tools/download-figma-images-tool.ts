import { z } from "zod";
import { FigmaService } from "../../services/figma.js";
import { Logger } from "../../utils/logger.js";

const parameters = {
  fileKey: z
    .string()
    .regex(/^[a-zA-Z0-9]+$/, "File key must be alphanumeric")
    .describe("The key of the Figma file containing the images"),
  nodes: z
    .object({
      nodeId: z
        .string()
        .regex(
          /^I?\d+[:|-]\d+(?:;\d+[:|-]\d+)*$/,
          "Node ID must be like '1234:5678' or 'I5666:180910;1:10515;1:10336'",
        )
        .describe("The ID of the Figma image node from get_figma_data output (found in node.id field). Format: '1234:5678' or with hyphens '1234-5678'."),
      imageRef: z
        .string()
        .optional()
        .describe(
          "REQUIRED for raster images (type='IMAGE'): The imageRef property from the node's fills array or imageRef field. OMIT for vector images (type='IMAGE-SVG'). This hash identifies the actual image asset in Figma.",
        ),
      fileName: z
        .string()
        .regex(
          /^[a-zA-Z0-9_.-]+\.(png|svg)$/,
          "File names must contain only letters, numbers, underscores, dots, or hyphens, and end with .png or .svg.",
        )
        .describe(
          "Desired filename for the uploaded S3 file. Use .svg for IMAGE-SVG nodes, .png for IMAGE nodes. Recommend format: 'type-nodeId.ext' (e.g., 'svg-195-3012.svg' or 'image-195-3184.png') to ensure uniqueness.",
        ),
      needsCropping: z
        .boolean()
        .optional()
        .describe("Set to true if the image has transforms/cropping in Figma. Found in node.imageDownloadArguments.needsCropping from get_figma_data output. Default: false."),
      cropTransform: z
        .array(z.array(z.number()))
        .optional()
        .describe("Transformation matrix for cropping. Copy from node.imageDownloadArguments.cropTransform in get_figma_data output. Only needed if needsCropping=true. Format: [[a,b,c],[d,e,f]] where each inner array is a row of the 2x3 matrix."),
      requiresImageDimensions: z
        .boolean()
        .optional()
        .describe("Set to true if you need width/height as CSS variables. Found in node.imageDownloadArguments.requiresImageDimensions. Default: false."),
      filenameSuffix: z
        .string()
        .optional()
        .describe(
          "Unique suffix for this specific crop/variant of an image. Copy from node.imageDownloadArguments.filenameSuffix in get_figma_data output. Used when multiple nodes reference the same imageRef but with different crops. Format: 6-char hex string (e.g., '157bc8').",
        ),
    })
    .array()
    .describe("Array of image nodes to download and upload to S3. Extract these from get_figma_data output by finding nodes with type='IMAGE-SVG' (vector) or type='IMAGE' (raster). Each entry should include the nodeId, appropriate fileName, and for raster images the imageRef. Include imageDownloadArguments properties (needsCropping, cropTransform, filenameSuffix) when present."),
  pngScale: z
    .number()
    .positive()
    .optional()
    .default(2)
    .describe(
      "Export scale for PNG images. Optional, defaults to 2 if not specified. Affects PNG images only.",
    ),
  figmaOAuthToken: z
    .string()
    .describe(
      "User's Figma OAuth access token obtained via OAuth flow. Required for all requests.",
    ),
};

const parametersSchema = z.object(parameters);
export type DownloadImagesParams = z.infer<typeof parametersSchema>;

// Enhanced handler function with image processing support
async function downloadFigmaImages(params: DownloadImagesParams) {
  try {
    const { fileKey, nodes, pngScale = 2, figmaOAuthToken } = parametersSchema.parse(params);

    // Get S3 config from environment - REQUIRED
    const { getS3ConfigFromEnv } = await import("../../utils/s3-upload.js");
    const s3Config = getS3ConfigFromEnv();

    if (!s3Config) {
      throw new Error(
        "S3 configuration not found. Required environment variables: AWS_REGION, AWS_BUCKET_NAME, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY",
      );
    }

    // Create FigmaService with the provided OAuth token (supports both OAuth and PAT)
    const figmaService = new FigmaService({
      figmaOAuthToken: figmaOAuthToken,
    });

    // Process nodes: collect unique downloads and track which requests they satisfy
    const downloadItems = [];
    const downloadToRequests = new Map<number, string[]>(); // download index -> requested filenames
    const seenDownloads = new Map<string, number>(); // uniqueKey -> download index

    for (const rawNode of nodes) {
      const { nodeId: rawNodeId, ...node } = rawNode;

      // Replace - with : in nodeId for our query—Figma API expects :
      const nodeId = rawNodeId?.replace(/-/g, ":");

      // Apply filename suffix if provided
      let finalFileName = node.fileName;
      if (node.filenameSuffix && !finalFileName.includes(node.filenameSuffix)) {
        const ext = finalFileName.split(".").pop();
        const nameWithoutExt = finalFileName.substring(0, finalFileName.lastIndexOf("."));
        finalFileName = `${nameWithoutExt}-${node.filenameSuffix}.${ext}`;
      }

      const downloadItem = {
        fileName: finalFileName,
        needsCropping: node.needsCropping || false,
        cropTransform: node.cropTransform,
        requiresImageDimensions: node.requiresImageDimensions || false,
      };

      if (node.imageRef) {
        // For imageRefs, check if we've already planned to download this
        const uniqueKey = `${node.imageRef}-${node.filenameSuffix || "none"}`;

        if (!node.filenameSuffix && seenDownloads.has(uniqueKey)) {
          // Already planning to download this, just add to the requests list
          const downloadIndex = seenDownloads.get(uniqueKey)!;
          const requests = downloadToRequests.get(downloadIndex)!;
          if (!requests.includes(finalFileName)) {
            requests.push(finalFileName);
          }

          // Update requiresImageDimensions if needed
          if (downloadItem.requiresImageDimensions) {
            downloadItems[downloadIndex].requiresImageDimensions = true;
          }
        } else {
          // New unique download
          const downloadIndex = downloadItems.length;
          downloadItems.push({ ...downloadItem, imageRef: node.imageRef });
          downloadToRequests.set(downloadIndex, [finalFileName]);
          seenDownloads.set(uniqueKey, downloadIndex);
        }
      } else {
        // Rendered nodes are always unique
        const downloadIndex = downloadItems.length;
        downloadItems.push({ ...downloadItem, nodeId });
        downloadToRequests.set(downloadIndex, [finalFileName]);
      }
    }

    // Use temp directory relative to current working directory
    const tempPath = "./temp-figma-images";

    const allDownloads = await figmaService.downloadImages(fileKey, tempPath, downloadItems, {
      pngScale,
      uploadToS3: true,
      s3Config,
    });

    const successCount = allDownloads.filter(Boolean).length;

    // Format results with S3 URLs
    const imagesList = allDownloads
      .map((result, index) => {
        const fileName = result.filePath.split("/").pop() || result.filePath;
        const dimensions = `${result.finalDimensions.width}x${result.finalDimensions.height}`;
        const cropStatus = result.wasCropped ? " (cropped)" : "";

        const dimensionInfo = result.cssVariables
          ? `${dimensions} | ${result.cssVariables}`
          : dimensions;

        // Show all the filenames that were requested for this download
        const requestedNames = downloadToRequests.get(index) || [fileName];
        const aliasText =
          requestedNames.length > 1
            ? ` (also requested as: ${requestedNames.filter((name: string) => name !== fileName).join(", ")})`
            : "";

        // S3 URL is always present now
        const s3Info = result.s3Url ? `\n  S3 URL: ${result.s3Url}` : "";

        return `- ${fileName}: ${dimensionInfo}${cropStatus}${aliasText}${s3Info}`;
      })
      .join("\n");

    return {
      content: [
        {
          type: "text" as const,
          text: `Uploaded ${successCount} images to S3:\n${imagesList}`,
        },
      ],
    };
  } catch (error) {
    Logger.error(`Error downloading images from ${params.fileKey}:`, error);
    return {
      isError: true,
      content: [
        {
          type: "text" as const,
          text: `Failed to download images: ${error instanceof Error ? error.message : String(error)}`,
        },
      ],
    };
  }
}

// Export tool configuration
export const downloadFigmaImagesTool = {
  name: "download_figma_images",
  description:
    "Download and upload Figma images to S3 in bulk, returning public URLs. Call this AFTER get_figma_data to process extracted images. Handles two image types: (1) IMAGE-SVG nodes (vector graphics - no imageRef needed), (2) IMAGE nodes with imageRef (raster images like photos - imageRef REQUIRED). The tool downloads images, applies cropping transforms if needed, uploads to S3 with public access, and returns the S3 URLs. Use the imageDownloadArguments from get_figma_data output to populate needsCropping, cropTransform, and filenameSuffix parameters for each image. Temporary files are automatically cleaned up.",
  parameters,
  handler: downloadFigmaImages,
} as const;
