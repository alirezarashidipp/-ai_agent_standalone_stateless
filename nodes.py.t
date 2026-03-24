from typing import Dict, Any
from state import GroomingSession, GroomingPhase
from schemas import JiraAnalysis
from llm_client import StructuredLLMClient

# Initialize Lead Engineer's LLM Client
llm = StructuredLLMClient()

def extraction_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 0: Requirement Extraction.
    Uses the JiraAnalysis schema to parse the 3Ws, Impact, and AC.
    """
    print(f"[NODE] Executing Extraction for phase: {state.phase}")
    
    system_prompt = "You are a Senior Requirement Engineer. Analyze the input for Jira Story elements."
    # Context injection: Current message + existing analysis state
    user_prompt = f"User Input: {state.last_user_message}\nExisting Context: {state.analysis.model_dump_json() if state.analysis else '{}'}"

    # Structured Output: LLM strictly follows your schemas.py
    new_analysis: JiraAnalysis = llm.query(system_prompt, user_prompt, JiraAnalysis)

    # State Update: Direct composition
    state.analysis = new_analysis
    
    # Transition Logic: 
    # Based on your schema's 'what.identified' and 'enforce_data_integrity' validator
    if not new_analysis.what.identified or new_analysis.grooming_questions:
        state.phase = GroomingPhase.CLARIFYING
    else:
        state.phase = GroomingPhase.REFINING_TECH

    return state.model_dump()

def clarification_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 1: Clarification. 
    In a stateless loop, this node simply re-triggers extraction with new user input.
    """
    print("[NODE] Executing Clarification")
    # Logic: Merge new answer into the analysis via extraction
    return extraction_node(state)

def tech_refinement_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 2: Tech Lead Analysis.
    Decides if more technical details are needed or moves to AC Review.
    """
    # Logic based on your ActionCategory and DetailLevel in schemas.py
    if state.analysis.what.the_level_of_details_in_intent == "no_details":
        state.phase = GroomingPhase.REFINING_TECH # Keep asking tech questions
    else:
        state.phase = GroomingPhase.REVIEWING_AC
        
    return state.model_dump()

def ac_review_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 3: Agile Coach Review.
    Final check for Agile Standards defined in your schema.
    """
    if "confirm" in state.last_user_message.lower():
        state.phase = GroomingPhase.FINALIZING
    else:
        # If not confirmed, we stay in REVIEWING_AC
        state.phase = GroomingPhase.REVIEWING_AC
        
    return state.model_dump()

def final_story_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 4: Story Generation.
    Finalizes the process and marks it as DONE.
    """
    state.phase = GroomingPhase.DONE
    # Formatting the final string based on all extracted fields
    state.final_jira_story = f"STORY: {state.analysis.what.intent_evidence}..."
    return state.model_dump()
