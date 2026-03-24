from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field, ConfigDict

class GroomingPhase(str, Enum):
    """
    Defining explicit phases for stateless routing.
    Each phase maps to a specific node in the graph.
    """
    START = "start"
    CLARIFYING = "clarifying"
    REFINING_TECH = "refining_tech"
    REVIEWING_AC = "reviewing_ac"
    FINALIZING = "finalizing"
    DONE = "done"

class CoreElements(BaseModel):
    """
    The '3Ws' requirements structure.
    """
    who: Optional[str] = None
    what: Optional[str] = None
    why: Optional[str] = None

class FinalStory(BaseModel):
    title: str
    description: str
    acceptance_criteria: List[str]
    technical_notes: Optional[str] = None

class GroomingSession(BaseModel):
    """
    The main State object. This is what gets serialized to JSON 
    and sent back to the client.
    """
    # Metadata for Routing
    phase: GroomingPhase = Field(default=GroomingPhase.START)
    
    # Requirement state (The Memory)
    core: CoreElements = Field(default_factory=CoreElements)
    
    # Technical Refinement state
    tech_questions: List[str] = Field(default_factory=list)
    tech_question_idx: int = 0
    
    # Acceptance Criteria state
    ac_draft: List[str] = Field(default_factory=list)
    
    # Final Result
    final_story: Optional[FinalStory] = None
    
    # Per-request Input (Stateless Context)
    last_user_message: str = ""
    
    # Pydantic V2 Configuration
    model_config = ConfigDict(
        use_enum_values=True,
        validate_assignment=True,
        arbitrary_types_allowed=True
    )

    def to_json(self) -> str:
        return self.model_dump_json()

    @classmethod
    def from_dict(cls, data: dict) -> "GroomingSession":
        return cls(**data)
