from typing import Dict, Any
from state import GroomingSession, GroomingPhase
# Assumes schemas like ExtractorOutput, ValidatorOutput, TechQuestionsOutput are defined
from schemas import ExtractorOutput, ValidatorOutput, TechQuestionsOutput, FinalStoryOutput
from llm_client import StructuredLLMClient
import yaml

# Load prompts globally
with open("prompts.yaml", "r", encoding="utf-8") as f:
    PROMPTS = yaml.safe_load(f)

llm = StructuredLLMClient()

def phase0_extractor(state: GroomingSession) -> Dict[str, Any]:
    """Phase 0: Zero-Shot Hydration"""
    if not state.raw_input:
        state.raw_input = state.last_user_message # Capture initial burst

    sys_prompt = PROMPTS["extractor"]["system"]
    result: ExtractorOutput = llm.query(sys_prompt, f"Raw input: {state.raw_input}", ExtractorOutput)
    
    state.who = result.who
    state.what = result.what
    state.why = result.why
    state.ac_evidence = result.ac_evidence
    
    # Edge Case Logic: Calculate missing fields
    state.missing_fields = [f for f in ["who", "what", "why"] if getattr(state, f) is None]
    
    if state.missing_fields:
        state.phase = GroomingPhase.PHASE1_LOCK # EC 2: Trigger Triad Lock
    else:
        state.phase = GroomingPhase.PHASE2_TECH_LEAD # EC 1: Bypass directly to Phase 2
        
    return state.model_dump()

def phase1_lock(state: GroomingSession) -> Dict[str, Any]:
    """Phase 1: JIT Validation & Triad Lock"""
    target_field = state.missing_fields[0] # The current field we are waiting for
    
    # Run Validator
    sys_prompt = PROMPTS["validator"]["system"].format(field=target_field)
    result: ValidatorOutput = llm.query(sys_prompt, f"User provided: {state.last_user_message}", ValidatorOutput)
    
    if result.is_valid:
        # Edge Case 1: Valid input -> Lock it, move forward
        setattr(state, target_field, result.normalized_value)
        state.missing_fields.pop(0)
        state.phase1_retries = 0
        state.last_rejection_reason = None
        
        # Check if triad is complete
        if not state.missing_fields:
            state.phase = GroomingPhase.PHASE2_TECH_LEAD
    else:
        # Edge Case 2 & 3: Gibberish -> Reject
        state.phase1_retries += 1
        state.last_rejection_reason = result.rejection_reason
        
        if state.phase1_retries >= 3:
            # Edge Case 3: Hard Abort
            state.is_aborted = True
            state.abort_reason = f"Hard Abort: Failed 3 times on '{target_field}'."
            state.phase = GroomingPhase.ABORTED

    # If not aborted and still missing fields, phase remains PHASE1_LOCK (Stateless Loop)
    return state.model_dump()

def phase2_tech_lead(state: GroomingSession) -> Dict[str, Any]:
    """Phase 2 Init: Extract Questions"""
    sys_prompt = PROMPTS["tech_lead"]["system"].format(what=state.what, why=state.why)
    result: TechQuestionsOutput = llm.query(sys_prompt, "Review and generate technical questions.", TechQuestionsOutput)
    
    if not result.questions:
        # Edge Case 3: No tech complexity
        state.phase = GroomingPhase.PHASE3_SYNTHESIZE
    else:
        # Prepare for sequential Q&A
        state.pending_questions = result.questions
        state.phase = GroomingPhase.PHASE2_ASK
        
    return state.model_dump()

def phase2_ask(state: GroomingSession) -> Dict[str, Any]:
    """Phase 2 Loop: Semantic Tech Grooming"""
    current_q = state.pending_questions[0]
    
    sys_prompt = PROMPTS["inline_validator"]["system"].format(question=current_q, answer=state.last_user_message)
    result: ValidatorOutput = llm.query(sys_prompt, f"Evaluate this answer: {state.last_user_message}", ValidatorOutput)
    
    if result.is_valid and result.normalized_value:
        # Edge Case 1: Valid answer -> Save as constraint
        state.tech_notes.append(f"Constraint derived from '{current_q}': {result.normalized_value}")
    # Edge Case 2: Dodge -> Ignore and do NOT append. Just move to next question.
    
    # Pop question regardless of answer (we don't get stuck on tech questions)
    state.pending_questions.pop(0)
    
    if not state.pending_questions:
        state.phase = GroomingPhase.PHASE3_SYNTHESIZE
        
    return state.model_dump()

def phase3_synthesize(state: GroomingSession) -> Dict[str, Any]:
    """Phase 3 Init: Global Synthesis"""
    tech_notes_str = "\n".join(state.tech_notes)
    
    sys_prompt = PROMPTS["agile_coach"]["system"].format(
        who=state.who, what=state.what, why=state.why,
        tech_notes=tech_notes_str, ac_evidence=state.ac_evidence or "",
        feedback=state.feedback_raw or ""
    )
    
    result: FinalStoryOutput = llm.query(sys_prompt, "Generate final Jira story.", FinalStoryOutput)
    state.final_story = result.story
    state.phase = GroomingPhase.PHASE3_FEEDBACK
    
    return state.model_dump()

def phase3_feedback(state: GroomingSession) -> Dict[str, Any]:
    """Phase 3 Loop: Global HITL"""
    user_msg = state.last_user_message.strip().lower()
    
    if "confirm" in user_msg:
        # Edge Case 1: Direct Confirm
        state.is_complete = True
        state.phase = GroomingPhase.DONE
        return state.model_dump()
        
    # Edge Case 2 & 3: Rewrite requested
    state.feedback_retries += 1
    
    if state.feedback_retries >= 3:
        # Edge Case 3: Force Commit
        state.is_complete = True
        state.phase = GroomingPhase.DONE
    else:
        # Edge Case 2: Route back to synthesis
        state.feedback_raw = state.last_user_message
        state.phase = GroomingPhase.PHASE3_SYNTHESIZE
        
    return state.model_dump()
