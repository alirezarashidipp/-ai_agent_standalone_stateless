from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field

class GroomingPhase(str, Enum):
    PHASE0_EXTRACT = "phase0_extract"
    PHASE1_LOCK = "phase1_lock"
    PHASE2_TECH_LEAD = "phase2_tech_lead"
    PHASE2_ASK = "phase2_ask"
    PHASE3_SYNTHESIZE = "phase3_synthesize"
    PHASE3_FEEDBACK = "phase3_feedback"
    DONE = "done"
    ABORTED = "aborted"

class GroomingSession(BaseModel):
    # Routing & Core Flow
    phase: GroomingPhase = Field(default=GroomingPhase.PHASE0_EXTRACT)
    last_user_message: str = ""
    
    # Phase 0/1: Triad Core
    raw_input: str = ""
    who: Optional[str] = None
    what: Optional[str] = None
    why: Optional[str] = None
    ac_evidence: Optional[str] = None
    missing_fields: List[str] = Field(default_factory=list)
    
    # Phase 1: Triad Lock Controls
    phase1_retries: int = 0
    last_rejection_reason: Optional[str] = None
    is_aborted: bool = False
    abort_reason: Optional[str] = None
    
    # Phase 2: Tech Grooming
    pending_questions: List[str] = Field(default_factory=list)
    tech_notes: List[str] = Field(default_factory=list)
    
    # Phase 3: Synthesis & HITL
    final_story: Optional[str] = None
    feedback_retries: int = 0
    feedback_raw: Optional[str] = None
    is_complete: bool = False
