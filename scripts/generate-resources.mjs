import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const resources = path.join(root, 'Resources');
const iconDirectory = path.join(resources, 'Assets.xcassets', 'AppIcon.appiconset');
fs.mkdirSync(iconDirectory, { recursive: true });

const sampleRate = 8000;
const seconds = 12;
const pcmSize = sampleRate * seconds * 2;
const wave = Buffer.alloc(44 + pcmSize);
wave.write('RIFF', 0);
wave.writeUInt32LE(36 + pcmSize, 4);
wave.write('WAVEfmt ', 8);
wave.writeUInt32LE(16, 16);
wave.writeUInt16LE(1, 20);
wave.writeUInt16LE(1, 22);
wave.writeUInt32LE(sampleRate, 24);
wave.writeUInt32LE(sampleRate * 2, 28);
wave.writeUInt16LE(2, 32);
wave.writeUInt16LE(16, 34);
wave.write('data', 36);
wave.writeUInt32LE(pcmSize, 40);
fs.writeFileSync(path.join(resources, 'silence.wav'), wave);

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, bytes) {
  const name = Buffer.from(type);
  const head = Buffer.alloc(4);
  const tail = Buffer.alloc(4);
  head.writeUInt32BE(bytes.length);
  tail.writeUInt32BE(crc32(Buffer.concat([name, bytes])));
  return Buffer.concat([head, name, bytes, tail]);
}
function segmentDistance(x, y, x1, y1, x2, y2) {
  const dx = x2 - x1, dy = y2 - y1;
  const t = Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(x - x1 - t * dx, y - y1 - t * dy);
}
const width = 1024;
const scanlines = Buffer.alloc((width * 3 + 1) * width);
for (let y = 0; y < width; y++) {
  for (let x = 0; x < width; x++) {
    const index = y * (width * 3 + 1) + 1 + x * 3;
    const dx = x - 465, dy = y - 512;
    const angle = Math.atan2(dy, dx);
    const ring = Math.abs(Math.hypot(dx, dy) - 245) < 42 && Math.abs(angle) > 0.72;
    const waveMark = segmentDistance(x, y, 515, 470, 515, 554) < 26 ||
      segmentDistance(x, y, 610, 415, 610, 609) < 26 ||
      segmentDistance(x, y, 705, 465, 705, 559) < 26;
    const rgb = ring || waveMark ? [255, 130, 100] : [14, 17, 22];
    scanlines[index] = rgb[0]; scanlines[index + 1] = rgb[1]; scanlines[index + 2] = rgb[2];
  }
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(width, 4); ihdr[8] = 8; ihdr[9] = 2;
const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(scanlines)), chunk('IEND', Buffer.alloc(0))]);
fs.writeFileSync(path.join(iconDirectory, 'AppIcon.png'), png);
fs.writeFileSync(path.join(iconDirectory, 'Contents.json'), JSON.stringify({
  images: [{ filename: 'AppIcon.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }],
  info: { author: 'xcode', version: 1 }
}, null, 2) + '\n');
fs.writeFileSync(path.join(resources, 'Assets.xcassets', 'Contents.json'), JSON.stringify({
  info: { author: 'xcode', version: 1 }
}, null, 2) + '\n');
console.log('Recursos generados: icono RGB de 1024 px y audio PCM silencioso de 12 segundos.');
