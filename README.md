# 赛博小镇 - AI NPC对话系统

基于HelloAgents框架的AI小镇模拟游戏,展示多智能体系统在游戏中的应用。

## 🎮 优化提升

- 后端通过给NPC接入API，实现智能对话，包括记忆、好感度、自主行为等
- 接入 Agnes API
- 智能对话功能曾存在网络请求失败/超时（result=13）问题
- 问题在于NPC回复生成和好感度分析需要两次LLM调用，每次调用都需要等待响应
- 通过将好感度分析改为后台异步执行，网络请求失败/超时问题得到解决
- 回复慢的主要原因在于LLM调用需要等待响应（免费还要什么自行车）

## 🎮 功能特性

- ✅ 3个AI NPC (张三、李四、王五)
- ✅ 智能对话系统
- ✅ 记忆系统 (短期+长期记忆)
- ✅ 好感度系统 (5个等级)
- ✅ NPC自主行为 (闲逛、工作)
- ✅ 完整的日志系统

## 🛠️ 技术栈

- **游戏引擎:** Godot 4.x
- **后端框架:** FastAPI + Python 3.10+
- **AI框架:** HelloAgents
- **LLM:** OpenAI GPT-4 (可配置其余的LLM服务)

## 📦 快速开始

详见 [SETUP_GUIDE.md](SETUP_GUIDE.md)

## 📚 文档

- [安装配置指南](SETUP_GUIDE.md)
- [对话日志系统](DIALOGUE_LOG_GUIDE.md)
- [好感度系统](AFFINITY_SYSTEM_GUIDE.md)
- [记忆系统](MEMORY_SYSTEM_GUIDE.md)

## 📖 教程

本项目是《Hello-agents》教材第15章的配套案例。

## 📄 许可证

CC BY-NC-SA 4.0
