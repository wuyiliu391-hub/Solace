const fs = require('fs');
const zlib = require('zlib');

const input = 'build/app/outputs/flutter-apk/app-release.apk';
const output = 'solace/app-release.apk.gz';

const data = fs.readFileSync(input);
const gzipped = zlib.gzipSync(data, { level: zlib.constants.Z_BEST_COMPRESSION });
fs.writeFileSync(output, gzipped);

const inputMB = (data.length / 1024 / 1024).toFixed(1);
const outputMB = (gzipped.length / 1024 / 1024).toFixed(1);
console.log(`APK: ${inputMB}MB -> GZ: ${outputMB}MB`);