import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const project = read('project.yml');
const workflow = read('.github/workflows/ios.yml');
let checks = 0;
function check(name, action) { action(); checks++; console.log(`OK ${name}`); }

check('Ambos targets incluyen la misma definición de Live Activity', () => {
  assert.equal((project.match(/path: Shared/g) || []).length, 2);
  assert.match(project, /path: Resources\s+buildPhase: resources/);
});
check('El job macOS solo se ejecuta para repositorios públicos', () => {
  assert.match(workflow, /if: \$\{\{ github\.event\.repository\.private == false \}\}/);
  assert.match(workflow, /runs-on: macos-15\s/);
  assert.doesNotMatch(workflow, /macos[^\n]*-(?:large|xlarge)/);
});
check('Compilación manual, sin caché ni almacenamiento de artefactos facturable', () => {
  assert.match(workflow, /workflow_dispatch/);
  assert.doesNotMatch(workflow, /schedule:|pull_request_target:|^  push:/m);
  assert.doesNotMatch(workflow, /upload-artifact|actions\/cache/);
  assert.match(workflow, /gh release create/);
  assert.match(workflow, /--draft --target/);
  assert.match(workflow, /timeout-minutes: 25/);
});
check('No se requieren certificados ni secretos en GitHub', () => {
  assert.doesNotMatch(workflow, /secrets\./);
  assert.match(workflow, /CODE_SIGNING_ALLOWED=NO/);
  assert.match(workflow, /swift test/);
});
check('OAuth usa PKCE y el único permiso es leer reproducción', () => {
  const auth = read('App/Services/SpotifyAuth.swift');
  assert.match(auth, /code_challenge_method.*S256/);
  assert.match(auth, /user-read-currently-playing/);
  assert.doesNotMatch(auth, /user-modify-playback-state|client_secret\s*:/);
  assert.match(read('App/Services/LoopbackCallback.swift'), /requiredLocalEndpoint = \.hostPort\(host: "127\.0\.0\.1"/);
});
check('El acceso queda en Keychain de este dispositivo', () => {
  const keychain = read('App/Services/KeychainStore.swift');
  assert.match(keychain, /kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly/);
  assert.match(keychain, /SecItemDelete/);
});
check('No se habilitan micrófono, GPS, push ni excepciones ATS generales', () => {
  assert.doesNotMatch(project, /NSMicrophoneUsageDescription|NSLocation|aps-environment|NSAllowsArbitraryLoads|carplay-audio/);
});
check('PCM válido y completamente silencioso', () => {
  const wav = fs.readFileSync(path.join(root, 'Resources/silence.wav'));
  assert.equal(wav.toString('ascii', 0, 4), 'RIFF');
  assert.equal(wav.toString('ascii', 8, 16), 'WAVEfmt ');
  assert.equal(wav.readUInt16LE(20), 1);
  assert.equal(wav.readUInt16LE(22), 1);
  assert.equal(wav.length - 44, wav.readUInt32LE(40));
  assert.equal(wav.readUInt32LE(40) / wav.readUInt32LE(28), 12);
  assert(wav.subarray(44).every(value => value === 0));
});
check('Icono PNG RGB de 1024 px sin transparencia', () => {
  const png = fs.readFileSync(path.join(root, 'Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'));
  assert.equal(png.readUInt32BE(16), 1024);
  assert.equal(png.readUInt32BE(20), 1024);
  assert.equal(png[25], 2);
  const payloads = [];
  for (let i = 8; i < png.length;) {
    const length = png.readUInt32BE(i), type = png.toString('ascii', i + 4, i + 8);
    if (type === 'IDAT') payloads.push(png.subarray(i + 8, i + 8 + length));
    i += length + 12;
  }
  assert.equal(zlib.inflateSync(Buffer.concat(payloads)).length, (1024 * 3 + 1) * 1024);
});
check('Hay pruebas Swift para pausas, búsquedas y reproducción obsoleta', () => {
  const tests = read('Tests/LyricsCoreTests/LyricsCoreTests.swift');
  assert((tests.match(/func test/g) || []).length >= 14);
  assert.match(tests, /testPausedPlaybackDoesNotAdvance/);
  assert.match(tests, /testStalePlaybackIsNotTreatedAsLive/);
  assert.match(tests, /testMatchingRejectsAnotherVersionAndArtist/);
});
check('No hay credenciales evidentes dentro de los archivos de texto', () => {
  const scan = directory => {
    for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
      if (['.git', '.build', 'build', 'dist'].includes(item.name)) continue;
      const file = path.join(directory, item.name);
      if (item.isDirectory()) scan(file);
      else if (/\.(swift|yml|md|json)$/.test(item.name)) {
        const source = fs.readFileSync(file, 'utf8');
        assert.doesNotMatch(source, /(?:ghp_|github_pat_|sk_live_)[A-Za-z0-9_]{15,}/);
        assert.doesNotMatch(source, /-----BEGIN (?:RSA |EC )?PRIVATE KEY-----/);
      }
    }
  };
  scan(root);
});
console.log(`${checks} comprobaciones locales correctas. Estas comprobaciones NO compilan Swift ni prueban CarPlay.`);
