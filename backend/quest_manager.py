"""任务系统管理器 - 多步骤任务链

功能:
- 管理任务定义(有序目标)和玩家进度
- 完成一个目标解锁下一个(顺序约束)
- 支持两类目标: 与NPC对话(talk_to_npc)、与物体交互(interact_object)
- 完成整条任务链发放奖励(复用好感度系统)

注意: 进度为纯内存存储(与好感度系统一致),后端重启即丢失。
"""

from typing import Dict, List, Optional

# ==================== 任务定义(静态,类似 agents.py 的 NPC_ROLES) ====================
QUEST_DEFINITIONS: Dict[str, dict] = {
    "quest_intro": {
        "quest_id": "quest_intro",
        "title": "新人报到",
        "description": "熟悉办公室的同事和环境",
        "objectives": [  # 有序列表,索引即步骤序号
            {
                "objective_id": "talk_zhang",
                "description": "去工位区和张三打个招呼",
                "type": "talk_to_npc",       # 目标类型
                "target": "张三",            # 匹配 NPC 名
            },
            {
                "objective_id": "get_file",
                "description": "去会议室拿到需求文件",
                "type": "interact_object",   # 目标类型
                "target": "meeting_room_file",  # 匹配物体 object_id
            },
            {
                "objective_id": "give_li",
                "description": "把文件交给李四",
                "type": "talk_to_npc",
                "target": "李四",
            },
        ],
        "reward": {
            "affinity": {"李四": 10, "张三": 5}  # 完成后发放的好感度奖励
        },
    }
}


class QuestManager:
    """任务系统管理器

    进度结构 self.progress[player_id][quest_id]:
        {
            "quest_id": str,
            "status": "not_started" | "in_progress" | "completed",
            "current_index": int,          # 当前激活的 objective 索引
            "completed_objectives": [str],  # 已完成的 objective_id 列表
        }
    """

    def __init__(self, relationship_manager=None):
        """初始化任务管理器

        Args:
            relationship_manager: 好感度管理器实例(用于发放奖励),可为 None(模拟模式)
        """
        self.relationship_manager = relationship_manager
        # {player_id: {quest_id: progress}}
        self.progress: Dict[str, Dict[str, dict]] = {}
        print("📜 任务系统管理器已初始化")

    def _ensure_started(self, quest_id: str, player_id: str) -> dict:
        """惰性初始化任务进度: 首次访问时置为 in_progress"""
        if player_id not in self.progress:
            self.progress[player_id] = {}

        if quest_id not in self.progress[player_id]:
            self.progress[player_id][quest_id] = {
                "quest_id": quest_id,
                "status": "in_progress",  # 本示例任务默认自动开始
                "current_index": 0,
                "completed_objectives": [],
            }

        return self.progress[player_id][quest_id]

    def get_quest_state(self, player_id: str = "player") -> List[dict]:
        """返回该玩家所有任务的进度快照(含 objective 描述与完成标记)"""
        result = []

        for quest_id, definition in QUEST_DEFINITIONS.items():
            progress = self._ensure_started(quest_id, player_id)
            completed_ids = set(progress["completed_objectives"])

            objectives = []
            for obj in definition["objectives"]:
                objectives.append({
                    "objective_id": obj["objective_id"],
                    "description": obj["description"],
                    "type": obj["type"],
                    "target": obj["target"],
                    "completed": obj["objective_id"] in completed_ids,
                })

            result.append({
                "quest_id": quest_id,
                "title": definition["title"],
                "description": definition["description"],
                "status": progress["status"],
                "current_index": progress["current_index"],
                "objectives": objectives,
            })

        return result

    def get_quest(self, quest_id: str, player_id: str = "player") -> Optional[dict]:
        """返回单个任务的进度快照,不存在则返回 None"""
        if quest_id not in QUEST_DEFINITIONS:
            return None
        for quest in self.get_quest_state(player_id):
            if quest["quest_id"] == quest_id:
                return quest
        return None

    def handle_action(self, player_id: str, action_type: str, target: str) -> dict:
        """处理玩家交互事件,尝试推进任务(核心逻辑,后端唯一裁决点)

        只匹配「当前激活的那一个目标」,天然实现顺序约束。
        跳步交互(目标未解锁)会被静默忽略。

        Args:
            player_id: 玩家ID
            action_type: "talk_to_npc" 或 "interact_object"
            target: NPC名 或 物体object_id

        Returns:
            {advanced, quest_id, completed_objective, quest_completed, reward_applied}
        """
        for quest_id, definition in QUEST_DEFINITIONS.items():
            progress = self._ensure_started(quest_id, player_id)

            if progress["status"] != "in_progress":
                continue

            objectives = definition["objectives"]
            idx = progress["current_index"]
            if idx >= len(objectives):
                continue

            cur = objectives[idx]

            # 命中当前激活目标 → 推进
            if cur["type"] == action_type and cur["target"] == target:
                progress["completed_objectives"].append(cur["objective_id"])
                progress["current_index"] += 1

                quest_completed = False
                reward_applied = {}

                if progress["current_index"] >= len(objectives):
                    progress["status"] = "completed"
                    quest_completed = True
                    reward_applied = self._apply_reward(quest_id, player_id)

                print(f"📜 任务推进: {quest_id} 完成目标 '{cur['objective_id']}' "
                      f"(进度 {progress['current_index']}/{len(objectives)})"
                      + (" ✅ 任务完成!" if quest_completed else ""))

                return {
                    "advanced": True,
                    "quest_id": quest_id,
                    "completed_objective": cur["objective_id"],
                    "quest_completed": quest_completed,
                    "reward_applied": reward_applied,
                }

        # 没匹配到任何激活目标,静默忽略
        return {
            "advanced": False,
            "quest_id": None,
            "completed_objective": None,
            "quest_completed": False,
            "reward_applied": {},
        }

    def _apply_reward(self, quest_id: str, player_id: str) -> dict:
        """发放任务完成奖励(好感度),relationship_manager 为 None 时跳过"""
        reward = QUEST_DEFINITIONS[quest_id].get("reward", {})
        affinity_reward = reward.get("affinity", {})

        if not affinity_reward:
            return {}

        if self.relationship_manager is None:
            print("⚠️  好感度管理器未就绪,跳过任务奖励发放")
            return {}

        applied = {}
        for npc_name, delta in affinity_reward.items():
            current = self.relationship_manager.get_affinity(npc_name, player_id)
            new_value = current + delta
            self.relationship_manager.set_affinity(npc_name, new_value, player_id)
            applied[npc_name] = delta
            print(f"🎁 任务奖励: {npc_name} 好感度 +{delta} ({current:.0f} → {new_value:.0f})")

        return applied


# 全局单例
_quest_manager = None


def get_quest_manager() -> QuestManager:
    """获取任务管理器单例

    必须复用 npc_manager 的 relationship_manager 同一实例,
    否则奖励会写入孤立字典,/affinities 查不到。
    """
    global _quest_manager
    if _quest_manager is None:
        from agents import get_npc_manager
        rm = get_npc_manager().relationship_manager
        _quest_manager = QuestManager(rm)
    return _quest_manager
