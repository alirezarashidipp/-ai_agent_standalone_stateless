import yaml
from typing import Literal
from pydantic import BaseModel, Field
from langgraph.graph import StateGraph, START, END

from state import WorkflowState, ExtractorOutput, ValidatorOutput, TechQuestionsOutput
from llm_client import StructuredLLMClient

with open("prompts.yaml", "r", encoding="utf-8") as f:
    PROMPTS = yaml.safe_load(f)

llm = StructuredLLMClient()

class FinalStoryOutput(BaseModel):
    story: str = Field(description="The fully synthesized Jira Agile Story")

def phase0_extract(state: WorkflowState) -> dict:
    # Idempotency
    if state.get("who") or state.get("current_phase") != "phase0":
        return {}
        
    sys_prompt = PROMPTS["extractor"]["system"]
    result = llm.query(sys_prompt, f"Raw input: {state['raw_input']}", ExtractorOutput)
    
    missing = [k for k in ["who", "what", "why"] if not getattr(result, k)]
    
    return {
        "who": result.who, "what": result.what, "why": result.why,
        "ac_evidence": result.ac_evidence, "missing_fields": missing,
        "current_phase": "phase1" if missing else "phase2"
    }

def phase1_lock(state: WorkflowState) -> dict:
    missing = state.get("missing_fields", [])
    if not missing:
        return {"current_phase": "phase2"}
        
    target = missing[0]
    
    # Needs input, prompt the external system
    if not state.get("user_injected_response"):
        retries = state.get("phase1_retries", 0)
        if retries >= 3:
            return {"is_aborted": True, "abort_reason": f"Hard Abort on '{target}'.", "action_required": False}
            
        rejection = state.get("last_rejection_reason")
        prompt_msg = f"[REJECTED]: {rejection}\nMissing '{target}'." if rejection else f"Missing '{target}'."
        return {"action_required": True, "action_prompt": prompt_msg}
        
    # Process injected state
    user_val = state["user_injected_response"]
    sys_prompt = PROMPTS["validator"]["system"].format(field=target)
    result = llm.query(sys_prompt, f"User provided: {user_val}", ValidatorOutput)
    
    if result.is_valid:
        new_missing = missing[1:]
        return {
            target: result.normalized_value, "missing_fields": new_missing,
            "phase1_retries": 0, "last_rejection_reason": None,
            "user_injected_response": None, "action_required": False,
            "current_phase": "phase1" if new_missing else "phase2"
        }
    else:
        return {
            "phase1_retries": state.get("phase1_retries", 0) + 1,
            "last_rejection_reason": result.rejection_reason,
            "user_injected_response": None, "action_required": False
        }

def phase2_tech_lead(state: WorkflowState) -> dict:
    if state.get("pending_questions") or state.get("tech_notes"):
        return {}
    sys_prompt = PROMPTS["tech_lead"]["system"].format(what=state["what"], why=state["why"])
    result = llm.query(sys_prompt, "Review and generate technical questions.", TechQuestionsOutput)
    return {"pending_questions": result.questions, "current_phase": "phase2_ask"}

def phase2_ask_questions(state: WorkflowState) -> dict:
    questions = state.get("pending_questions", [])
    if not questions:
        return {"current_phase": "phase3"}
        
    current_q = questions[0]
    
    if not state.get("user_injected_response"):
        return {"action_required": True, "action_prompt": f"[Tech Lead]: {current_q}"}
        
    user_answer = state["user_injected_response"]
    sys_prompt = PROMPTS["inline_validator"]["system"].format(question=current_q, answer=user_answer)
    result = llm.query(sys_prompt, f"Evaluate this answer: {user_answer}", ValidatorOutput)
    
    new_notes = state.get("tech_notes", [])
    if result.is_valid and result.normalized_value:
        new_notes.append(f"Constraint derived from '{current_q}': {result.normalized_value}")
        
    return {
        "pending_questions": questions[1:], "tech_notes": new_notes,
        "user_injected_response": None, "action_required": False,
        "current_phase": "phase2_ask" if len(questions) > 1 else "phase3"
    }

def phase3_synthesize(state: WorkflowState) -> dict:
    if state.get("final_story") and not state.get("feedback_raw"):
        return {}
        
    tech_notes_str = "\n".join(state.get("tech_notes", []))
    feedback = state.get("feedback_raw", "")
    
    sys_prompt = PROMPTS["agile_coach"]["system"].format(
        who=state["who"], what=state["what"], why=state["why"],
        tech_notes=tech_notes_str, ac_evidence=state.get("ac_evidence", ""),
        feedback=feedback
    )
    
    result = llm.query(sys_prompt, "Generate final Jira story.", FinalStoryOutput)
    return {"final_story": result.story, "current_phase": "phase3_feedback", "feedback_raw": None}

def phase3_feedback(state: WorkflowState) -> dict:
    retries = state.get("feedback_retries", 0)
    if retries >= 3:
        return {"is_complete": True, "action_required": False}
        
    if not state.get("user_injected_response"):
        prompt = f"\n[Agile Coach Output]:\n{state['final_story']}\n\nType 'confirm' to accept, or provide feedback:"
        return {"action_required": True, "action_prompt": prompt}
        
    user_feedback = state["user_injected_response"]
    if user_feedback.strip().lower() == "confirm":
        return {"is_complete": True, "user_injected_response": None, "action_required": False}
        
    return {
        "feedback_raw": user_feedback, "feedback_retries": retries + 1,
        "user_injected_response": None, "action_required": False,
        "current_phase": "phase3"
    }

# ---------------------------------------------------------
# Routing Logic (Stateless)
# ---------------------------------------------------------
def route_start(state: WorkflowState) -> str:
    phase = state.get("current_phase", "phase0")
    routes = {"phase0": "phase0_extract", "phase1": "phase1_lock", "phase2": "phase2_tech_lead", 
              "phase2_ask": "phase2_ask_questions", "phase3": "phase3_synthesize", "phase3_feedback": "phase3_feedback"}
    return routes.get(phase, "phase0_extract")

def route_after_phase0(state: WorkflowState) -> str:
    return "phase1_lock" if state.get("current_phase") == "phase1" else "phase2_tech_lead"

def route_after_phase1(state: WorkflowState) -> Literal["phase1_lock", "phase2_tech_lead", "__end__"]:
    if state.get("action_required") or state.get("is_aborted"): return END
    return "phase1_lock" if state.get("current_phase") == "phase1" else "phase2_tech_lead"

def route_after_phase2_ask(state: WorkflowState) -> Literal["phase2_ask_questions", "phase3_synthesize", "__end__"]:
    if state.get("action_required"): return END
    return "phase2_ask_questions" if state.get("current_phase") == "phase2_ask" else "phase3_synthesize"

def route_after_phase3_feedback(state: WorkflowState) -> Literal["phase3_synthesize", "__end__"]:
    if state.get("action_required") or state.get("is_complete"): return END
    return "phase3_synthesize"

builder = StateGraph(WorkflowState)

builder.add_node("phase0_extract", phase0_extract)
builder.add_node("phase1_lock", phase1_lock)
builder.add_node("phase2_tech_lead", phase2_tech_lead)
builder.add_node("phase2_ask_questions", phase2_ask_questions)
builder.add_node("phase3_synthesize", phase3_synthesize)
builder.add_node("phase3_feedback", phase3_feedback)

builder.add_conditional_edges(START, route_start)
builder.add_conditional_edges("phase0_extract", route_after_phase0)
builder.add_conditional_edges("phase1_lock", route_after_phase1)
builder.add_edge("phase2_tech_lead", "phase2_ask_questions")
builder.add_conditional_edges("phase2_ask_questions", route_after_phase2_ask)
builder.add_edge("phase3_synthesize", "phase3_feedback")
builder.add_conditional_edges("phase3_feedback", route_after_phase3_feedback)

# Compiled purely stateless. Safe for high-availability load balancing.
graph = builder.compile()
