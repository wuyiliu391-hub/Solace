'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "5b917d7a0e4e0ee1fb878f847163f157",
"assets/AssetManifest.bin.json": "43ef61973de62be4dfb5dbb049210ccb",
"assets/AssetManifest.json": "6786f237e96ccaac078042768538b842",
"assets/assets/sky.mp3": "61b3875a6251ecc273df975d85d3f9f1",
"assets/assets/stickers/default_pack/metadata.json": "6bc1a0a290717ddb6e4012a9983be1d4",
"assets/assets/stickers/default_pack/mmexport1779624243874.jpeg": "dc0ca42bf18b87bc0ad87f1302ea04de",
"assets/assets/stickers/default_pack/mmexport1779624244097.jpeg": "233e17dfd09ee53ee076b52bc511773c",
"assets/assets/stickers/default_pack/mmexport1779624244229.jpeg": "44a7de0ffc76e27e406f81e748b2bc98",
"assets/assets/stickers/default_pack/mmexport1779624244316.jpeg": "94faa49755320572ba1ad468387f346d",
"assets/assets/stickers/default_pack/mmexport1779624244428.jpeg": "b9266df44b01cf193fb0a65887c9c85e",
"assets/assets/stickers/default_pack/mmexport1779624244507.jpeg": "c6f462870ad53bc4dac19a3e9c7db7db",
"assets/assets/stickers/default_pack/mmexport1779624244566.jpeg": "20e8db4898570ab60f33a2194fec0acb",
"assets/assets/stickers/default_pack/mmexport1779624244627.jpeg": "00e2bbcfc05f6d51efa8f4da2b1137f3",
"assets/assets/stickers/default_pack/mmexport1779624244693.jpeg": "b98b99fe2e4993e0445cdeaac761cc99",
"assets/assets/stickers/default_pack/mmexport1779624244756.jpeg": "ac1c2f4dac75c0e9734ed1abee060599",
"assets/assets/stickers/default_pack/mmexport1779624244815.jpeg": "3610b632a7da43cd446f4f401df123d5",
"assets/assets/stickers/default_pack/mmexport1779624244872.jpeg": "883384638a7dd2214aa5fbc5a9f46ae0",
"assets/assets/stickers/default_pack/mmexport1779624244940.jpeg": "d17ca7b15677ca48cd7b2b3b2332af1c",
"assets/assets/stickers/default_pack/mmexport1779624245002.jpeg": "878a9ebc2dc4791e1df1eb04dcec2fbf",
"assets/assets/stickers/default_pack/mmexport1779624245064.jpeg": "29a4e1d723f887d2cd76383d3692dafc",
"assets/assets/stickers/default_pack/mmexport1779624245161.jpeg": "7dafa1a55e2d997e508f26ce61d21e1f",
"assets/assets/stickers/default_pack/mmexport1779624245220.jpeg": "f2e7265f59fe0e57e9c9de7d543fbf42",
"assets/assets/stickers/default_pack/mmexport1779624590587.jpeg": "2e26f50fdc5a1ea22ca5977f4842f779",
"assets/assets/stickers/default_pack/mmexport1779624590868.jpeg": "47895ac3965cc8c1e4fb68e4b324bdfb",
"assets/assets/stickers/default_pack/mmexport1779624590956.jpeg": "d1a0379f3496068319b9e88d02a86216",
"assets/assets/stickers/default_pack/mmexport1779624591045.jpeg": "82bc4721f39f25ace93d38d8e899c443",
"assets/assets/stickers/default_pack/mmexport1779624591124.jpeg": "5af4d951a37d6902fc137753d4cb60e4",
"assets/assets/stickers/default_pack/mmexport1779624591201.jpeg": "06e2f5196be0db9d5524b5d6fc3963a7",
"assets/assets/stickers/default_pack/mmexport1779624591274.jpeg": "ee1b9e5d727ef38b67cff8816c8d831a",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "0968a650de11458745d5e8ec00b4d27e",
"assets/NOTICES": "ce2ec211465d2a16fc87fa785081ec6f",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "e986ebe42ef785b27164c36a9abc7818",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"canvaskit/canvaskit.js": "66177750aff65a66cb07bb44b8c6422b",
"canvaskit/canvaskit.js.symbols": "48c83a2ce573d9692e8d970e288d75f7",
"canvaskit/canvaskit.wasm": "1f237a213d7370cf95f443d896176460",
"canvaskit/chromium/canvaskit.js": "671c6b4f8fcc199dcc551c7bb125f239",
"canvaskit/chromium/canvaskit.js.symbols": "a012ed99ccba193cf96bb2643003f6fc",
"canvaskit/chromium/canvaskit.wasm": "b1ac05b29c127d86df4bcfbf50dd902a",
"canvaskit/skwasm.js": "694fda5704053957c2594de355805228",
"canvaskit/skwasm.js.symbols": "262f4827a1317abb59d71d6c587a93e2",
"canvaskit/skwasm.wasm": "9f0c0c02b82a910d12ce0543ec130e60",
"canvaskit/skwasm.worker.js": "89990e8c92bcb123999aa81f7e203b1c",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "f393d3c16b631f36852323de8e583132",
"flutter_bootstrap.js": "5099230e4b513fd34bc11ff1c691981d",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "c24116c77b761843cfcdabe4f8e8f408",
"/": "c24116c77b761843cfcdabe4f8e8f408",
"main.dart.js": "6fe43047b1271245f7b26b8ac5325e28",
"manifest.json": "a4f0afd2f26870a087718ae02e5a85cc",
"version.json": "25afaf41f41228985e48d5233fee5f5d"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
