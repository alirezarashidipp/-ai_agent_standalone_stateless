import json
from typing import Any, Dict
from state import GroomingSession, GroomingPhase
from graph import app

def run_pipeline_step(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Stateless Logic Controller.
    Takes client payload, reconstructs state, executes one tick of the FSM, and serializes the result.
    """
    session_data = payload.get("session", {})
    user_message = payload.get("message", "").strip()
    
    try:
        session = GroomingSession(**session_data)
        session.last_user_message = user_message
        
        # Guard clause for terminal states
        if session.phase in [GroomingPhase.DONE, GroomingPhase.ABORTED]:
            return {
                "session": session.model_dump(),
                "status": "terminated",
                "message": "Session has already reached a terminal state."
            }
            
        final_state_output = app.invoke(session)
        
        updated_session = GroomingSession(**final_state_output) if isinstance(final_state_output, dict) else final_state_output

        # State rendering for UI
        display_message = _render_ui_message(updated_session)

        return {
            "session": updated_session.model_dump(),
            "status": "success",
            "message": display_message
        }

    except Exception as e:
        print(f"[FATAL] System fault during pipeline execution: {e}")
        return {
            "session": session_data,
            "status": "error",
            "error_detail": str(e)
        }

def _render_ui_message(state: GroomingSession) -> str:
    """
    Translates the internal state and FSM constraints into a user-facing prompt.
    """
    if state.phase == GroomingPhase.ABORTED:
        return f"[SYSTEM ABORT] {state.abort_reason}"
        
    if state.phase == GroomingPhase.PHASE1_LOCK:
        base_msg = f"Missing core requirement: '{state.missing_fields[0].upper()}'. Please provide it."
        if state.last_rejection_reason:
            return f"[Validation Failed] {state.last_rejection_reason}\n\n{base_msg} (Attempt {state.phase1_retries}/3)"
        return base_msg
        
    if state.phase == GroomingPhase.PHASE2_ASK:
        if state.pending_questions:
            return f"[Tech Lead] {state.pending_questions[0]}"
            
    if state.phase == GroomingPhase.PHASE3_FEEDBACK:
        msg = f"Draft Story generated:\n\n{state.final_story}\n\nType 'confirm' to accept, or provide your edits."
        if state.feedback_retries > 0:
            msg += f"\n(Revision {state.feedback_retries}/3)"
        return msg
        
    if state.phase == GroomingPhase.DONE:
        if state.feedback_retries >= 3:
            return f"[Force Commit] Maximum revisions reached. Final Story locked:\n\n{state.final_story}"
        return f"[Success] Jira Story finalized:\n\n{state.final_story}"
        
    return "Processing transition..."

if __name__ == "__main__":
    # Local CLI Simulation
    mock_payload = {
        "session": {}, 
        "message": "Build a login page"
    }
    result = run_pipeline_step(mock_payload)
    print(json.dumps(result, indent=2))
