from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field, ConfigDict
from schemas import JiraAnalysis  # Importing your existing schema as the source

class GroomingPhase(str, Enum):
    """
    Explicit phases for stateless routing.
    Each phase correlates to a specific Node in LangGraph.
    """
    START = "start"
    CLARIFYING = "clarifying"
    REFINING_TECH = "refining_tech"
    REVIEWING_AC = "reviewing_ac"
    FINALIZING = "finalizing"
    DONE = "done"

class GroomingSession(BaseModel):
    """
    The Master State object. 
    This is the ONLY object transferred between Client and Kubernetes/Spyder.
    """
    # 1. Flow Control
    phase: GroomingPhase = Field(default=GroomingPhase.START)
    
    # 2. Core Data (Using your JiraAnalysis from schemas.py)
    # This stores everything: Who, What, Why, Impact, AC, and Questions.
    analysis: Optional[JiraAnalysis] = None
    
    # 3. Context & Tracking
    last_user_message: str = ""
    tech_question_idx: int = 0
    
    # 4. Final Output storage
    final_jira_story: Optional[str] = None

    # Pydantic V2 Configuration for production performance and safety
    model_config = ConfigDict(
        use_enum_values=True,
        validate_assignment=True,
        populate_by_name=True,
        arbitrary_types_allowed=True
    )

    def serialize(self) -> str:
        """Converts state to JSON string for client-side storage."""
        return self.model_dump_json()

    @classmethod
    def deserialize(cls, data: dict) -> "GroomingSession":
        """Reconstructs state from client-provided dictionary."""
        return cls(**data)
