from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field

class GroomingPhase(str, Enum):
    START = "start"
    CLARIFYING = "clarifying"
    REFINING_TECH = "refining_tech"
    REVIEWING_AC = "reviewing_ac"
    FINALIZING = "finalizing"
    DONE = "done"

class CoreElements(BaseModel):
    who: Optional[str] = None
    what: Optional[str] = None
    why: Optional[str] = None

class FinalStory(BaseModel):
    title: str
    description: str
    acceptance_criteria: List[str]
    technical_notes: Optional[str] = None

class GroomingSession(BaseModel):
    # Process tracking
    phase: GroomingPhase = Field(default=GroomingPhase.START)
    
    # Requirements state
    core: CoreElements = Field(default_factory=CoreElements)
    
    # Phase 2: Tech refinement state
    tech_questions: List[str] = Field(default_factory=list)
    tech_question_idx: int = 0
    
    # Phase 3: Acceptance Criteria state
    ac_draft: List[str] = Field(default_factory=list)
    
    # Outputs
    final_story: Optional[FinalStory] = None
    
    # Transient fields (Inputs from current request)
    last_user_message: str = ""
    
    class Config:
        use_enum_values = True
        validate_assignment = True

# Helper for API layer
def session_to_json(session: GroomingSession) -> str:
    return session.model_dump_json()

def json_to_session(data: dict) -> GroomingSession:
    return GroomingSession(**data)
