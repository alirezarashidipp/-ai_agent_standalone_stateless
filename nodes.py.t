from typing import Dict, Any
from state import GroomingSession, GroomingPhase
from schemas import JiraAnalysis
from llm_client import StructuredLLMClient
import logging

logger = logging.getLogger(__name__)
llm = StructuredLLMClient()

def extraction_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 0: Extracts requirement components using JiraAnalysis schema.
    Updates the phase to CLARIFYING or REFINING_TECH based on completeness.
    """
    system_prompt = "You are a Senior Business Analyst. Extract Who, What, and Why."
    user_prompt = f"Current Input: {state.last_user_message}\nExisting Context: {state.core.model_dump_json()}"

    # Using Structured Output to ensure schema adherence
    analysis: JiraAnalysis = llm.query(system_prompt, user_prompt, JiraAnalysis)

    # Partial update logic
    if analysis.who.identified:
        state.core.who = analysis.who.evidence
    if analysis.what.identified:
        state.core.what = analysis.what.intent_evidence
    if analysis.why.identified:
        state.core.why = analysis.why.value_evidence
    
    # State Transition
    is_complete = all([analysis.who.identified, analysis.what.identified, analysis.why.identified])
    
    if is_complete:
        state.phase = GroomingPhase.REFINING_TECH
    else:
        state.tech_questions = analysis.grooming_questions
        state.phase = GroomingPhase.CLARIFYING

    return state.model_dump()

def clarification_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 1: Processes user feedback for missing core elements.
    Reruns extraction logic with new context.
    """
    return extraction_node(state)

def tech_refinement_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 2: Tech Lead analyzes technical gaps.
    """
    if not state.tech_questions:
        # Simulate Tech Lead analysis
        state.tech_questions = ["What is the expected concurrent user count?", "Is there a specific DB preference?"]
        state.phase = GroomingPhase.REFINING_TECH
    else:
        # Move to AC phase once tech questions are handled
        state.phase = GroomingPhase.REVIEWING_AC
        
    return state.model_dump()

def ac_review_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 3: Agile Coach generates/refines Acceptance Criteria.
    Waiting for 'confirm' message to proceed.
    """
    if "confirm" in state.last_user_message.lower():
        state.phase = GroomingPhase.FINALIZING
    else:
        if not state.ac_draft:
            state.ac_draft = ["AC 1: Must support OAuth2", "AC 2: Response time < 200ms"]
        state.phase = GroomingPhase.REVIEWING_AC
        
    return state.model_dump()

def final_story_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 4: Final output generation.
    """
    state.phase = GroomingPhase.DONE
    return state.model_dump()
