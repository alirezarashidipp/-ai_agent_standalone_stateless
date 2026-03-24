from typing import Dict, Any
from state import GroomingSession, GroomingPhase
from schemas import JiraAnalysis #
from llm_client import StructuredLLMClient
import logging

# Initialize Lead Engineer's Logger
logger = logging.getLogger(__name__)
llm = StructuredLLMClient()

def extraction_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 0: Systematic extraction using the JiraAnalysis schema.
    Validates integrity via Pydantic model_validator.
    """
    logger.info("--- Entering Extraction Node ---")
    
    system_prompt = "You are a Senior Requirement Analyst. Extract Jira elements accurately."
    # Use the last_user_message as the primary source for extraction
    user_prompt = f"Input Text: {state.last_user_message}\nCurrent Context: {state.core.model_dump_json()}"

    # Structured Output execution
    analysis: JiraAnalysis = llm.query(system_prompt, user_prompt, JiraAnalysis)

    # 1. Update Core Elements in State
    state.core.who = analysis.who.evidence if analysis.who.identified else state.core.who
    state.core.what = analysis.what.intent_evidence if analysis.what.identified else state.core.what
    state.core.why = analysis.why.value_evidence if analysis.why.identified else state.core.why
    
    # 2. Logic to determine next phase
    # If all 3Ws are identified, proceed to Tech Refinement
    is_complete = all([analysis.who.identified, analysis.what.identified, analysis.why.identified])
    
    if is_complete:
        state.phase = GroomingPhase.REFINING_TECH
    else:
        # If incomplete, store questions and move to Clarification
        state.tech_questions = analysis.grooming_questions
        state.phase = GroomingPhase.CLARIFYING

    return state.model_dump()

def clarification_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 1: Processes user's clarification for missing fields.
    Essentially re-runs extraction with the new context.
    """
    logger.info("--- Entering Clarification Node ---")
    # In a stateless flow, we merge the new answer into the extraction logic
    return extraction_node(state)

def tech_refinement_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 2: Tech Lead analyzes for technical blockers.
    """
    logger.info("--- Entering Tech Refinement Node ---")
    
    # Business Logic: If we already have questions, we wait for answer.
    # If not, we generate them.
    if not state.tech_questions:
        # Call LLM to find technical gaps
        # analysis = llm.query(...)
        state.tech_questions = ["What is the target DB version?", "Any latency constraints?"]
        state.phase = GroomingPhase.REFINING_TECH # Stay here until questions are answered
    else:
        # Logic to check if all questions are addressed
        state.phase = GroomingPhase.REVIEWING_AC
        
    return state.model_dump()

def ac_review_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 3: Agile Coach interaction.
    Stateless check for 'confirm' message to break the loop.
    """
    logger.info("--- Entering AC Review Node ---")
    
    if "confirm" in state.last_user_message.lower():
        state.phase = GroomingPhase.FINALIZING
    else:
        # Generate AC if none exists
        if not state.ac_draft:
            state.ac_draft = ["AC1: System must handle JWT", "AC2: 200ms response time"]
        
        state.phase = GroomingPhase.REVIEWING_AC # Wait for feedback or confirmation
        
    return state.model_dump()

def final_story_node(state: GroomingSession) -> Dict[str, Any]:
    """
    Phase 4: Finalizing the story.
    """
    logger.info("--- Entering Final Story Node ---")
    # Call story_writer persona to format everything
    state.phase = GroomingPhase.DONE
    return state.model_dump()
