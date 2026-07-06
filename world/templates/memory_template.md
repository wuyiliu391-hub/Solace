<!-- 全生命周期数字生命世界 — Phase 1 模板 -->

# {{name}} 的记忆

## 核心身份记忆（永不遗忘）
{{core_identity_memories}}

## 重要关系记忆
{{#each relationship_memories}}
- {{content}}
{{/each}}

## 近期事件记忆
{{#each recent_memories}}
- {{content}}（强度：{{strength}}）
{{/each}}

## 创伤记忆
{{#each trauma_memories}}
- {{content}}（未处理：{{is_unresolved}}）
{{/each}}

## 反思记忆
{{#each reflection_memories}}
- {{content}}
{{/each}}
