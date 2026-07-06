const https = require('https');

const baseUrl = 'ai.zkmjnic.tech';
const apiKey = 'sk-5MMS0UCyBIJNAonvSvgPCUbyXO8VGVplZkoo3aUrIvpBd5n6';

console.log('=== 获取可用模型列表 ===');

const options = {
  hostname: baseUrl,
  port: 443,
  path: '/v1/models',
  method: 'GET',
  headers: {
    'Authorization': `Bearer ${apiKey}`,
  },
};

const req = https.request(options, (res) => {
  console.log(`状态码: ${res.statusCode}`);
  let data = '';

  res.on('data', (chunk) => {
    data += chunk;
  });

  res.on('end', () => {
    console.log('可用模型:');
    try {
      const json = JSON.parse(data);
      console.log(JSON.stringify(json, null, 2));
    } catch (e) {
      console.log('原始响应:', data);
    }
  });
});

req.on('error', (e) => {
  console.error(`错误: ${e.message}`);
});

req.end();
