/**
 * gpt-image-2 图片生成测试
 * 用法: node tools/test_image_gen.js
 */

const BASE_URL = 'https://aiapi1.cc.cd/v1';
const API_KEY = 'sk-YFBVzRty8x4wgsHZu16liX8YowT401pTg3K66kos8KPxrWnA';

async function testImageGen() {
  console.log('='.repeat(60));
  console.log('gpt-image-2 图片生成测试');
  console.log(`Endpoint: ${BASE_URL}`);
  console.log('='.repeat(60));

  // 测试1: 标准图片生成 API
  console.log('\n--- 测试1: /images/generations ---');
  try {
    const res = await fetch(`${BASE_URL}/images/generations`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${API_KEY}`,
      },
      body: JSON.stringify({
        model: 'gpt-image-2',
        prompt: 'A cute anime girl with bunny ears, smiling, simple background',
        n: 1,
        size: '1024x1024',
        response_format: 'b64_json',
      }),
    });

    console.log(`[HTTP ${res.status}]`);
    const text = await res.text();
    if (res.ok) {
      const data = JSON.parse(text);
      if (data.data && data.data.length > 0) {
        const b64 = data.data[0].b64_json;
        if (b64) {
          console.log(`[结果] ✅ 图片生成成功，base64 长度: ${b64.length}`);
          // 保存图片
          const fs = require('fs');
          const buffer = Buffer.from(b64, 'base64');
          fs.writeFileSync('tools/test_output.png', buffer);
          console.log('[保存] 图片已保存到 tools/test_output.png');
        } else if (data.data[0].url) {
          console.log(`[结果] ✅ 图片生成成功，URL: ${data.data[0].url}`);
        } else {
          console.log(`[结果] ⚠️ 返回数据格式未知: ${JSON.stringify(data).substring(0, 300)}`);
        }
      } else {
        console.log(`[结果] ⚠️ 返回无 data: ${text.substring(0, 500)}`);
      }
    } else {
      console.log(`[结果] ❌ 失败: ${text.substring(0, 500)}`);
    }
  } catch (e) {
    console.log(`[错误] ${e.message}`);
  }

  // 测试2: chat/completions 方式（部分代理通过 chat 接口转发图片生成）
  console.log('\n--- 测试2: /chat/completions with gpt-image-2 ---');
  try {
    const res = await fetch(`${BASE_URL}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${API_KEY}`,
      },
      body: JSON.stringify({
        model: 'gpt-image-2',
        messages: [
          { role: 'user', content: 'Generate an image of a cute anime bunny girl' },
        ],
      }),
    });

    console.log(`[HTTP ${res.status}]`);
    const text = await res.text();
    if (res.ok) {
      console.log(`[结果] ✅ 成功: ${text.substring(0, 500)}`);
    } else {
      console.log(`[结果] ❌ 失败: ${text.substring(0, 500)}`);
    }
  } catch (e) {
    console.log(`[错误] ${e.message}`);
  }

  // 测试3: 列出可用模型
  console.log('\n--- 测试3: /models (列出可用模型) ---');
  try {
    const res = await fetch(`${BASE_URL}/models`, {
      headers: { 'Authorization': `Bearer ${API_KEY}` },
    });
    console.log(`[HTTP ${res.status}]`);
    const text = await res.text();
    if (res.ok) {
      const data = JSON.parse(text);
      const models = data.data || [];
      const imageModels = models.filter(m =>
        (m.id || '').toLowerCase().includes('image') ||
        (m.id || '').toLowerCase().includes('dall')
      );
      console.log(`[总模型数] ${models.length}`);
      console.log(`[图片相关模型] ${imageModels.length > 0 ? imageModels.map(m => m.id).join(', ') : '未找到'}`);
      // 显示所有模型ID
      const allIds = models.map(m => m.id).sort();
      console.log(`[所有模型] ${allIds.join(', ')}`);
    } else {
      console.log(`[结果] ${text.substring(0, 500)}`);
    }
  } catch (e) {
    console.log(`[错误] ${e.message}`);
  }

  console.log('\n测试完成');
}

testImageGen();