import fs from "fs";
import crypto from "crypto";
import path from "path";
import { fileURLToPath } from "url";

// Get current directory
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Get assets directory from command line argument or use default
const assetsDir = process.argv[2] || path.join(__dirname, "../dist");
console.error(`Using assets directory: ${assetsDir}`);
const manifest = {};

// Recursive function to process all files in directory and subdirectories
function processDirectory(dir, basePath = '') {
  fs.readdirSync(dir, { withFileTypes: true }).forEach((dirent) => {
    const fullPath = path.join(dir, dirent.name);
    const relativePath = path.join(basePath, dirent.name);
    
    if (dirent.isDirectory()) {
      // Process subdirectory recursively
      processDirectory(fullPath, relativePath);
    } else {
      // Process file
      const fileContent = fs.readFileSync(fullPath);
      
      // Generate SHA-256 hash and encode in Base64
      const hash = crypto.createHash("sha256").update(fileContent).digest("base64");
      
      // Use forward slashes for paths in manifest
      const manifestPath = `/${relativePath.replace(/\\/g, '/')}`;
      manifest[manifestPath] = {
        hash: `sha256-${hash}`,
        size: fileContent.length,
      };
    }
  });
}

// Start processing from root assets directory
processDirectory(assetsDir);

// Output manifest to stdout for capture by shell script
console.log(JSON.stringify(manifest, null, 2));
