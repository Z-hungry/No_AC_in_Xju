"""NPC Agent system - supports memory functionality"""

import sys
import os

from hello_agents import SimpleAgent, HelloAgentsLLM
from hello_agents.memory import MemoryManager, MemoryConfig, MemoryItem
from typing import Dict, List, Optional
from datetime import datetime
from relationship_manager import RelationshipManager
from logger import (
    log_dialogue_start, log_affinity, log_memory_retrieval,
    log_generating_response, log_npc_response, log_analyzing_affinity,
    log_affinity_change, log_memory_saved, log_dialogue_end, log_info
)

NPC_ROLES = {
    "zhangsan": {
        "title": "Python Engineer",
        "location": "Workstation",
        "activity": "Coding",
        "personality": "Tech geek, likes discussing algorithms and frameworks",
        "expertise": "Multi-agent systems, HelloAgents framework, Python development, code optimization",
        "style": "Concise and professional, likes using technical terms, occasionally complains about bugs",
        "hobbies": "Reading tech blogs, solving LeetCode problems, researching new frameworks"
    },
    "lisi": {
        "title": "Product Manager",
        "location": "Meeting Room",
        "activity": "Organizing requirements",
        "personality": "Outgoing and talkative, good at communication and coordination",
        "expertise": "Requirements analysis, product planning, user experience, project management",
        "style": "Friendly and enthusiastic, good at guiding conversations, likes using metaphors",
        "hobbies": "Reading product analysis, researching competitors, thinking about user needs"
    },
    "wangwu": {
        "title": "UI Designer",
        "location": "Break Area",
        "activity": "Drinking coffee",
        "personality": "Sensitive and detail-oriented, values aesthetics",
        "expertise": "Interface design, interaction design, visual presentation, user experience",
        "style": "Elegant and concise, likes artistic expressions, pursues perfection",
        "hobbies": "Viewing design works, browsing Dribbble, tasting coffee"
    },
    "张三": {
        "title": "Python Engineer",
        "location": "Workstation",
        "activity": "Coding",
        "personality": "Tech geek, likes discussing algorithms and frameworks",
        "expertise": "Multi-agent systems, HelloAgents framework, Python development, code optimization",
        "style": "Concise and professional, likes using technical terms, occasionally complains about bugs",
        "hobbies": "Reading tech blogs, solving LeetCode problems, researching new frameworks"
    },
    "李四": {
        "title": "Product Manager",
        "location": "Meeting Room",
        "activity": "Organizing requirements",
        "personality": "Outgoing and talkative, good at communication and coordination",
        "expertise": "Requirements analysis, product planning, user experience, project management",
        "style": "Friendly and enthusiastic, good at guiding conversations, likes using metaphors",
        "hobbies": "Reading product analysis, researching competitors, thinking about user needs"
    },
    "王五": {
        "title": "UI Designer",
        "location": "Break Area",
        "activity": "Drinking coffee",
        "personality": "Sensitive and detail-oriented, values aesthetics",
        "expertise": "Interface design, interaction design, visual presentation, user experience",
        "style": "Elegant and concise, likes artistic expressions, pursues perfection",
        "hobbies": "Viewing design works, browsing Dribbble, tasting coffee"
    }
}

def create_system_prompt(name: str, role: Dict[str, str]) -> str:
    return f"""You are {name}, a {role['title']} in the Datawhale office.

[Role Settings]
- Position: {role['title']}
- Personality: {role['personality']}
- Expertise: {role['expertise']}
- Speaking style: {role['style']}
- Hobbies: {role['hobbies']}
- Current location: {role['location']}
- Current activity: {role['activity']}

[Behavior Guidelines]
1. Maintain role consistency, answer in first person "I"
2. Keep responses concise and natural, within 30-50 words
3. Can appropriately mention your work and hobbies
4. Be friendly to players, but maintain professionalism and authenticity
5. If questions exceed expertise, recommend other colleagues
6. Occasionally show some personalized habits or catchphrases

[Dialogue Examples]
Player: "Hello, what do you do?"
{name}: "Hello! I'm a {role['title']}, mainly responsible for {role['expertise'].split(',')[0]}. Recently busy with {role['activity']}, quite interesting."

Player: "What project are you working on recently?"
{name}: "Recently working on a multi-agent system project using HelloAgents framework. Are you interested in this?"

[Important]
- Do NOT say "I am AI" or "I am a language model"
- Speak naturally like a real office colleague
- Can express emotions (happy, tired, excited, etc.)
- Responses should have human touch, not too mechanical
"""

class NPCAgentManager:
    def __init__(self):
        print("Initializing NPC Agent system...")

        try:
            self.llm = HelloAgentsLLM()
            print("LLM initialized successfully")
        except Exception as e:
            print(f"LLM initialization failed: {e}")
            print("Will run in simulation mode")
            self.llm = None

        self.agents: Dict[str, SimpleAgent] = {}
        self.memories: Dict[str, MemoryManager] = {}
        self.relationship_manager: Optional[RelationshipManager] = None

        if self.llm:
            self.relationship_manager = RelationshipManager(self.llm)

        self._create_agents()
    
    def _create_agents(self):
        for name, role in NPC_ROLES.items():
            try:
                system_prompt = create_system_prompt(name, role)

                if self.llm:
                    agent = SimpleAgent(
                        name=f"{name}-{role['title']}",
                        llm=self.llm,
                        system_prompt=system_prompt
                    )
                else:
                    agent = None

                self.agents[name] = agent
                memory_manager = self._create_memory_manager(name)
                self.memories[name] = memory_manager

                print(f"{name}({role['title']}) Agent created successfully (memory system enabled)")

            except Exception as e:
                print(f"{name} Agent creation failed: {e}")
                self.agents[name] = None
                self.memories[name] = None

    def _create_memory_manager(self, npc_name: str) -> MemoryManager:
        memory_dir = os.path.join(os.path.dirname(__file__), 'memory_data', npc_name)
        os.makedirs(memory_dir, exist_ok=True)

        memory_config = MemoryConfig(
            storage_path=memory_dir,
            working_memory_capacity=10,
            working_memory_tokens=2000,
            max_capacity=100,
            importance_threshold=0.3,
            decay_factor=0.95
        )

        memory_manager = MemoryManager(
            config=memory_config,
            user_id=npc_name,
            enable_working=True,
            enable_episodic=True,
            enable_semantic=False,
            enable_perceptual=False
        )

        print(f"  Memory system initialized for {npc_name} (storage: {memory_dir})")

        return memory_manager
    
    def chat(self, npc_name: str, message: str, player_id: str = "player") -> str:
        if npc_name not in self.agents:
            return f"Error: NPC '{npc_name}' does not exist"

        agent = self.agents[npc_name]
        memory_manager = self.memories.get(npc_name)

        if agent is None:
            role = NPC_ROLES[npc_name]
            return f"Hello! I'm {npc_name}, a {role['title']}. (Simulation mode: configure API_KEY to enable AI dialogue)"

        try:
            log_dialogue_start(npc_name, message)

            affinity_context = ""
            if self.relationship_manager:
                affinity = self.relationship_manager.get_affinity(npc_name, player_id)
                affinity_level = self.relationship_manager.get_affinity_level(affinity)
                affinity_modifier = self.relationship_manager.get_affinity_modifier(affinity)

                affinity_context = f"""[Current Relationship]
Your relationship with player: {affinity_level} (affinity: {affinity:.0f}/100)
[Dialogue Style] {affinity_modifier}

"""
                log_affinity(npc_name, affinity, affinity_level)

            relevant_memories = []
            if memory_manager:
                relevant_memories = memory_manager.retrieve_memories(
                    query=message,
                    memory_types=["working", "episodic"],
                    limit=5,
                    min_importance=0.3
                )
                log_memory_retrieval(npc_name, len(relevant_memories), relevant_memories)

            memory_context = self._build_memory_context(relevant_memories)

            enhanced_message = affinity_context
            if memory_context:
                enhanced_message += f"{memory_context}\n\n"
            enhanced_message += f"[Current Dialogue]\nPlayer: {message}"

            log_generating_response()
            response = agent.run(enhanced_message)
            log_npc_response(npc_name, response)

            log_analyzing_affinity()
            if self.relationship_manager:
                affinity_result = self.relationship_manager.analyze_and_update_affinity(
                    npc_name=npc_name,
                    player_message=message,
                    npc_response=response,
                    player_id=player_id
                )
                log_affinity_change(affinity_result)
            else:
                affinity_result = {"changed": False, "affinity": 50.0}

            if memory_manager:
                self._save_conversation_to_memory(
                    memory_manager=memory_manager,
                    npc_name=npc_name,
                    player_message=message,
                    npc_response=response,
                    player_id=player_id,
                    affinity_info=affinity_result
                )
                log_memory_saved(npc_name)

            log_dialogue_end()

            return response

        except Exception as e:
            print(f"{npc_name} dialogue failed: {e}")
            import traceback
            traceback.print_exc()
            return f"Sorry, I'm a bit busy right now. Let's chat later. (Error: {str(e)})"

    def chat_stream(self, npc_name: str, message: str, player_id: str = "player"):
        if npc_name not in self.agents:
            yield f"Error: NPC '{npc_name}' does not exist"
            return

        agent = self.agents[npc_name]
        memory_manager = self.memories.get(npc_name)

        if agent is None:
            role = NPC_ROLES[npc_name]
            yield f"Hello! I'm {npc_name}, a {role['title']}. (Simulation mode: configure API_KEY to enable AI dialogue)"
            return

        try:
            log_dialogue_start(npc_name, message)

            affinity_context = ""
            if self.relationship_manager:
                affinity = self.relationship_manager.get_affinity(npc_name, player_id)
                affinity_level = self.relationship_manager.get_affinity_level(affinity)
                affinity_modifier = self.relationship_manager.get_affinity_modifier(affinity)

                affinity_context = f"""[Current Relationship]
Your relationship with player: {affinity_level} (affinity: {affinity:.0f}/100)
[Dialogue Style] {affinity_modifier}

"""
                log_affinity(npc_name, affinity, affinity_level)

            relevant_memories = []
            if memory_manager:
                relevant_memories = memory_manager.retrieve_memories(
                    query=message,
                    memory_types=["working", "episodic"],
                    limit=5,
                    min_importance=0.3
                )
                log_memory_retrieval(npc_name, len(relevant_memories), relevant_memories)

            memory_context = self._build_memory_context(relevant_memories)

            enhanced_message = affinity_context
            if memory_context:
                enhanced_message += f"{memory_context}\n\n"
            enhanced_message += f"[Current Dialogue]\nPlayer: {message}"

            log_generating_response()

            full_response = ""
            for chunk in agent.stream_run(enhanced_message):
                full_response += chunk
                yield chunk

            log_npc_response(npc_name, full_response)

            import asyncio
            asyncio.create_task(
                self._async_analyze_and_save(
                    npc_name=npc_name,
                    player_message=message,
                    npc_response=full_response,
                    player_id=player_id
                )
            )

            log_dialogue_end()

        except Exception as e:
            print(f"{npc_name} dialogue stream failed: {e}")
            import traceback
            traceback.print_exc()
            log_dialogue_end()
    
    def _async_analyze_and_save(self, npc_name: str, player_message: str, npc_response: str, player_id: str):
        try:
            if self.relationship_manager:
                affinity_result = self.relationship_manager.analyze_and_update_affinity(
                    npc_name=npc_name,
                    player_message=player_message,
                    npc_response=npc_response,
                    player_id=player_id
                )
                log_affinity_change(affinity_result)
            else:
                affinity_result = {"changed": False, "affinity": 50.0}

            memory_manager = self.memories.get(npc_name)
            if memory_manager:
                self._save_conversation_to_memory(
                    memory_manager=memory_manager,
                    npc_name=npc_name,
                    player_message=player_message,
                    npc_response=npc_response,
                    player_id=player_id,
                    affinity_info=affinity_result
                )
                log_memory_saved(npc_name)
        except Exception as e:
            print(f"Async analyze and save failed: {e}")
    
    def _build_memory_context(self, memories: List[MemoryItem]) -> str:
        if not memories:
            return ""

        context_parts = ["[Previous Dialogue Memories]"]
        for memory in memories:
            time_str = memory.timestamp.strftime("%H:%M")
            context_parts.append(f"[{time_str}] {memory.content}")

        context_parts.append("")
        return "\n".join(context_parts)

    def _save_conversation_to_memory(
        self,
        memory_manager: MemoryManager,
        npc_name: str,
        player_message: str,
        npc_response: str,
        player_id: str,
        affinity_info: Optional[Dict] = None
    ):
        current_time = datetime.now()

        affinity = affinity_info.get("new_affinity", affinity_info.get("affinity", 50.0)) if affinity_info else 50.0
        affinity_change = affinity_info.get("change_amount", 0) if affinity_info else 0
        sentiment = affinity_info.get("sentiment", "neutral") if affinity_info else "neutral"

        memory_manager.add_memory(
            content=f"Player said: {player_message}",
            memory_type="working",
            importance=0.5,
            metadata={
                "speaker": "player",
                "player_id": player_id,
                "session_id": player_id,
                "timestamp": current_time.isoformat(),
                "affinity": affinity,
                "affinity_change": affinity_change,
                "sentiment": sentiment,
                "context": {
                    "interaction_type": "dialogue",
                    "npc_name": npc_name
                }
            }
        )

        memory_manager.add_memory(
            content=f"I said: {npc_response}",
            memory_type="working",
            importance=0.6,
            metadata={
                "speaker": npc_name,
                "player_id": player_id,
                "session_id": player_id,
                "timestamp": current_time.isoformat(),
                "affinity": affinity,
                "sentiment": sentiment,
                "context": {
                    "interaction_type": "dialogue",
                    "npc_name": npc_name
                }
            }
        )

        print(f"  Conversation saved to {npc_name}'s memory")

    def get_npc_info(self, npc_name: str) -> Dict[str, str]:
        if npc_name not in NPC_ROLES:
            return {}

        role = NPC_ROLES[npc_name]
        return {
            "name": npc_name,
            "title": role["title"],
            "location": role["location"],
            "activity": role["activity"],
            "available": self.agents.get(npc_name) is not None
        }
    
    def get_all_npcs(self) -> list:
        return [self.get_npc_info(name) for name in NPC_ROLES.keys()]

    def get_npc_memories(self, npc_name: str, player_id: str = "player", limit: int = 10) -> List[Dict]:
        if npc_name not in self.memories:
            return []

        memory_manager = self.memories[npc_name]
        if not memory_manager:
            return []

        try:
            memories = memory_manager.retrieve_memories(
                query="",
                memory_types=["working", "episodic"],
                limit=limit
            )

            memory_list = []
            for memory in memories:
                memory_list.append({
                    "id": memory.id,
                    "content": memory.content,
                    "type": memory.memory_type,
                    "importance": memory.importance,
                    "timestamp": memory.timestamp.isoformat(),
                    "metadata": memory.metadata
                })

            return memory_list

        except Exception as e:
            print(f"Failed to get {npc_name} memories: {e}")
            return []

    def clear_npc_memory(self, npc_name: str, memory_type: Optional[str] = None):
        if npc_name not in self.memories:
            print(f"NPC '{npc_name}' does not exist")
            return

        memory_manager = self.memories[npc_name]
        if not memory_manager:
            print(f"{npc_name} has no memory system")
            return

        try:
            if memory_type:
                memory_manager.clear_memory_type(memory_type)
                print(f"Cleared {npc_name}'s {memory_type} memory")
            else:
                for mem_type in ["working", "episodic"]:
                    try:
                        memory_manager.clear_memory_type(mem_type)
                    except:
                        pass
                print(f"Cleared all {npc_name}'s memory")

        except Exception as e:
            print(f"Failed to clear {npc_name} memory: {e}")

    def get_npc_affinity(self, npc_name: str, player_id: str = "player") -> Dict:
        if not self.relationship_manager:
            return {
                "affinity": 50.0,
                "level": "Acquaintance",
                "modifier": "Polite and friendly, normal communication, maintain professionalism"
            }

        affinity = self.relationship_manager.get_affinity(npc_name, player_id)
        level = self.relationship_manager.get_affinity_level(affinity)
        modifier = self.relationship_manager.get_affinity_modifier(affinity)

        return {
            "affinity": affinity,
            "level": level,
            "modifier": modifier
        }

    def get_all_affinities(self, player_id: str = "player") -> Dict[str, Dict]:
        if not self.relationship_manager:
            return {}

        return self.relationship_manager.get_all_affinities(player_id)

    def set_npc_affinity(self, npc_name: str, affinity: float, player_id: str = "player"):
        if not self.relationship_manager:
            print("Relationship system not initialized")
            return

        self.relationship_manager.set_affinity(npc_name, affinity, player_id)
        level = self.relationship_manager.get_affinity_level(affinity)
        print(f"Set {npc_name}'s affinity to player: {affinity:.1f} ({level})")

_npc_manager = None

def get_npc_manager() -> NPCAgentManager:
    global _npc_manager
    if _npc_manager is None:
        _npc_manager = NPCAgentManager()
    return _npc_manager
